"""Invite-scoped SQLite state. Tokens are hashed; imported chat is never persisted."""
import hashlib
import json
import secrets
import sqlite3
import threading
import time
import uuid
from planner import generate, instant, iso, text, number, eligibility, validate_request, validate_plans

class APIError(Exception):
    def __init__(self, status, message): self.status, self.message = status, message

def digest(token): return hashlib.sha256(token.encode()).hexdigest()

def profile(value, participant_id):
    try:
        keys = {"id", "displayName", "ageRange", "maxBudget", "approximateArea", "availability", "busyIntervals", "calendarConnectionStatus"}
        if set(value) not in [keys, keys | {"location"}] or not text(value["displayName"], 60) or not text(value["approximateArea"], 120): raise ValueError()
        eligibility(value["ageRange"])
        if not number(value["maxBudget"], 0, 500): raise ValueError()
        start, end = instant(value["availability"]["start"]), instant(value["availability"]["end"])
        if not 5400 <= (end - start).total_seconds() <= 604800 or len(value["busyIntervals"]) > 500: raise ValueError()
        for interval in value["busyIntervals"]:
            if instant(interval["start"]) >= instant(interval["end"]): raise ValueError()
        if value["calendarConnectionStatus"] not in ["manual", "connected", "demo"]: raise ValueError()
        result = dict(value, id=participant_id)
        if value.get("location") is not None:
            location = value["location"]
            if set(location) - {"latitude", "longitude", "displayArea"} or not number(location["latitude"], -90, 90) or not number(location["longitude"], -180, 180): raise ValueError()
            if location.get("displayArea") is not None and not text(location["displayArea"], 120): raise ValueError()
            result["location"] = dict(location, latitude=round(location["latitude"], 2), longitude=round(location["longitude"], 2))
        return result
    except (KeyError, TypeError, ValueError, AttributeError): raise APIError(400, "Invalid participant context") from None

def free_intervals(person):
    cursor, end = instant(person["availability"]["start"]), instant(person["availability"]["end"])
    result = []
    for window in sorted(person["busyIntervals"], key=lambda w: instant(w["start"])):
        a, b = instant(window["start"]), instant(window["end"])
        if b <= cursor or a >= end: continue
        if a > cursor: result.append({"start": iso(cursor), "end": iso(min(a, end))})
        cursor = max(cursor, b)
    if cursor < end: result.append({"start": iso(cursor), "end": iso(end)})
    return result

def winner(session):
    people = {p["id"] for p in session["participants"]}
    latest = {(v["participantId"], v["planId"]): v for v in session["votes"] if v["participantId"] in people}
    ranked = []
    for index, plan in enumerate(session["planOptions"]):
        votes = [v for v in latest.values() if v["planId"] == plan["id"]]
        # Validate this plan using three unique copies to reuse the exact hard-constraint checks.
        copies = [dict(plan, id=f"eligible-{i}") for i in range(3)]
        if not votes or not session.get("context") or not validate_plans(copies, session["context"]): continue
        score = sum({"down": 2, "maybe": 1, "pass": 0}[v["value"]] for v in votes)
        ranked.append(((score, sum(v["value"] == "down" for v in votes), -sum(v["value"] == "pass" for v in votes), plan["groupFitScore"], -index), plan["id"]))
    return max(ranked)[1] if ranked else None

class Service:
    def __init__(self, model_call=None, database=":memory:"):
        self.model_call = model_call
        self.lock = threading.RLock()
        self.db = sqlite3.connect(database, check_same_thread=False)
        self.db.execute("PRAGMA foreign_keys = ON")
        self.db.execute("CREATE TABLE IF NOT EXISTS sessions (id TEXT PRIMARY KEY, state TEXT NOT NULL, invite_hash TEXT NOT NULL, expires REAL NOT NULL)")
        self.db.execute("CREATE TABLE IF NOT EXISTS members (session_id TEXT REFERENCES sessions(id) ON DELETE CASCADE, participant_id TEXT, token_hash TEXT UNIQUE, owner INTEGER, PRIMARY KEY(session_id, participant_id))")
        self.db.commit()
    def close(self): self.db.close()
    def save(self, session):
        session["revision"] += 1
        self.db.execute("UPDATE sessions SET state=? WHERE id=?", (json.dumps(session), session["id"]))
        self.db.commit()
        return session
    def reset(self, session):
        session.update(planOptions=[], votes=[], winningPlanId=None, context=None, source="demo")
    def add_member(self, session, value=None, owner=False):
        participant_id, token = str(uuid.uuid4()), secrets.token_urlsafe(32)
        if value is not None:
            person = profile(value, participant_id)
            session["participants"].append(person)
            session["readyParticipantIds"].append(participant_id)
        self.db.execute("INSERT INTO members VALUES (?, ?, ?, ?)", (session["id"], participant_id, digest(token), int(owner)))
        return participant_id, token
    def membership(self, session, participant_id, token, invite, owner):
        return {"session": session, "participantId": participant_id, "memberToken": token, "inviteToken": invite, "isOwner": owner}
    def dispatch(self, method, path, body, token):
        if method == "GET" and path == "/health": return {"status": "ok"}
        if method == "POST" and path == "/sidequest/plan": return generate(body, self.model_call)
        with self.lock:
            self.db.execute("DELETE FROM sessions WHERE expires < ?", (time.time(),)); self.db.commit()
            if method == "POST" and path == "/api/sessions":
                if set(body) != {"expectedParticipantCount"}: raise APIError(400, "Provide the expected number of people")
                count = body["expectedParticipantCount"]
                if type(count) is not int or not 1 <= count <= 12: raise APIError(400, "Choose between 1 and 12 people")
                session = {"id": str(uuid.uuid4()), "participants": [], "revision": 0,
                           "expectedParticipantCount": count, "readyParticipantIds": []}
                self.reset(session)
                invite = secrets.token_urlsafe(32)
                self.db.execute("INSERT INTO sessions VALUES (?, ?, ?, ?)", (session["id"], "{}", digest(invite), time.time() + 604800))
                pid, member_token = self.add_member(session, owner=True)
                return self.membership(self.save(session), pid, member_token, invite, True)
            parts = path.strip("/").split("/")
            if len(parts) not in [3, 4] or parts[:2] != ["api", "sessions"]: raise APIError(404, "Route not found")
            sid, action = parts[2], parts[3] if len(parts) == 4 else ""
            row = self.db.execute("SELECT state, invite_hash FROM sessions WHERE id=?", (sid,)).fetchone()
            if not row: raise APIError(404, "Session not found or expired")
            session = json.loads(row[0])
            member = self.db.execute("SELECT participant_id, owner FROM members WHERE session_id=? AND token_hash=?", (sid, digest(token))).fetchone()
            invited = secrets.compare_digest(row[1], digest(token))
            if not member and not invited: raise APIError(403, "Use the session invitation or your member token")
            member_ids = {row[0] for row in self.db.execute("SELECT participant_id FROM members WHERE session_id=?", (sid,))}
            # Existing sessions must explicitly complete Done before another generation.
            session.setdefault("expectedParticipantCount", len(member_ids))
            session.setdefault("readyParticipantIds", [])
            if method == "GET" and not action: return session
            if method != "POST": raise APIError(404, "Route not found")
            if action == "join":
                if not invited or set(body) != {"participant"}: raise APIError(403, "Invitation required")
                if len(member_ids) >= session["expectedParticipantCount"]: raise APIError(409, "Everyone in this session has already joined")
                pid, new_token = self.add_member(session, body["participant"])
                self.reset(session)
                return self.membership(self.save(session), pid, new_token, token, False)
            if not member: raise APIError(403, "Join with your own context first")
            pid, owner = member
            if action == "context":
                if set(body) != {"participant"}: raise APIError(400, "Only your own context may be updated")
                person = profile(body["participant"], pid)
                if any(p["id"] == pid for p in session["participants"]):
                    session["participants"] = [person if p["id"] == pid else p for p in session["participants"]]
                else:
                    session["participants"].append(person)
                if pid not in session["readyParticipantIds"]:
                    session["readyParticipantIds"].append(pid)
                self.reset(session)
                return self.save(session)
            if action == "venues":
                if not owner: raise APIError(403, "Only the organizer may attach resolved venues")
                if set(body) != {"revision", "venues"} or body["revision"] != session["revision"] or not session["planOptions"]:
                    raise APIError(409, "Plans changed; refresh before attaching venues")
                items = body["venues"]
                if (not isinstance(items, list) or len(items) != 3
                    or any(not isinstance(v, dict) or not isinstance(v.get("planId"), str) for v in items)
                    or {v["planId"] for v in items} != {p["id"] for p in session["planOptions"]}):
                    raise APIError(400, "Provide a venue result for each plan")
                for item in items:
                    if set(item) != {"planId", "venue"}: raise APIError(400, "Invalid venue result")
                    venue = item["venue"]
                    if venue is not None and (not isinstance(venue, dict) or set(venue) - {"name", "address", "latitude", "longitude", "openingHours"} or not text(venue.get("name"), 200)
                        or not number(venue.get("latitude"), -90, 90) or not number(venue.get("longitude"), -180, 180)
                        or (venue.get("address") is not None and not text(venue["address"], 500))
                        or (venue.get("openingHours") is not None and not text(venue["openingHours"], 255))):
                        raise APIError(400, "Invalid venue result")
                resolved = {v["planId"]: v["venue"] for v in items}
                session["planOptions"] = [dict(p, venue=resolved[p["id"]]) for p in session["planOptions"]]
                return self.save(session)
            if action == "vote":
                if set(body) != {"planId", "value"} or body["value"] not in ["down", "maybe", "pass"]: raise APIError(400, "Invalid vote")
                if session["winningPlanId"] or body["planId"] not in [p["id"] for p in session["planOptions"]]: raise APIError(409, "Poll changed; refresh the session")
                session["votes"] = [v for v in session["votes"] if (v["participantId"], v["planId"]) != (pid, body["planId"])]
                session["votes"].append(dict(body, participantId=pid))
                return self.save(session)
            if action == "finalize":
                if not owner: raise APIError(403, "Only the organizer may finalize")
                selected = winner(session)
                if not selected: raise APIError(409, "At least one eligible plan needs a vote")
                session["winningPlanId"] = selected
                return self.save(session)
            if action != "plan": raise APIError(404, "Route not found")
            if not owner: raise APIError(403, "Only the organizer may generate plans")
            if set(body) != {"selectedMessages", "candidateTimeWindows", "timeZone"}: raise APIError(400, "Invalid planning request")
            if (len(member_ids) != session["expectedParticipantCount"] or
                set(session["readyParticipantIds"]) != member_ids or
                {p["id"] for p in session["participants"]} != member_ids):
                raise APIError(409, "Waiting for everyone to finish their context and tap Done")
            people = [{"id": p["id"], "ageRange": p["ageRange"], "maxBudget": p["maxBudget"], "approximateArea": p["approximateArea"], "availability": free_intervals(p)} for p in session["participants"]]
            request = dict(body, participants=people)
            validate_request(request)
            revision = session["revision"]
        result = generate(request, self.model_call)
        with self.lock:
            latest = self.db.execute("SELECT state FROM sessions WHERE id=?", (sid,)).fetchone()
            if not latest or json.loads(latest[0])["revision"] != revision: raise APIError(409, "Context changed; refresh and generate again")
            session.update(planOptions=result["plans"], source=result["source"], votes=[], winningPlanId=None,
                           context=dict(request, selectedMessages=[]))
            return self.save(session)
