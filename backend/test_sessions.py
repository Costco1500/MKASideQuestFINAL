import copy
import tempfile
import unittest
from concurrent.futures import ThreadPoolExecutor
from server import Service, APIError
from test_planner import context

def profile(name="Alex", budget=15):
    return {"id": "client-cannot-choose", "displayName": name, "ageRange": "18–20", "maxBudget": budget,
            "approximateArea": "Midtown", "availability": {"start": "2026-10-01T17:00:00Z", "end": "2026-10-01T22:00:00Z"},
            "busyIntervals": [], "calendarConnectionStatus": "manual"}

class SessionTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.service = Service(database=self.temp.name + "/state.sqlite", model_call=lambda _: {"plans": []})
        self.owner = self.service.dispatch("POST", "/api/sessions", {"participant": profile()}, "")
        self.path = "/api/sessions/" + self.owner["session"]["id"]
    def tearDown(self): self.service.close(); self.temp.cleanup()
    def call(self, suffix, body=None, token=None, method="POST"):
        return self.service.dispatch(method, self.path + suffix, body or {}, token or self.owner["memberToken"])
    def join(self): return self.call("/join", {"participant": profile("Maya")}, self.owner["inviteToken"])
    def plan(self):
        request = context()
        return self.call("/plan", {"selectedMessages": request["selectedMessages"], "candidateTimeWindows": request["candidateTimeWindows"], "timeZone": "UTC"})
    def test_join_authentication_and_own_context_only(self):
        member = self.join()
        self.assertEqual(len(member["session"]["participants"]), 2)
        self.assertNotEqual(member["participantId"], "client-cannot-choose")
        with self.assertRaises(APIError): self.call("", token="bad-token", method="GET")
        updated = self.call("/context", {"participant": profile("Maya", 0)}, member["memberToken"])
        self.assertEqual(updated["participants"][0]["maxBudget"], 15)
        self.assertEqual(updated["participants"][1]["maxBudget"], 0)
    def test_multimember_votes_upsert_and_finalize_survive_restart(self):
        member = self.join(); self.plan()
        with ThreadPoolExecutor() as pool:
            list(pool.map(lambda token: self.call("/vote", {"planId": "plan-2", "value": "down"}, token), [member["memberToken"], self.owner["memberToken"]]))
        session = self.call("/vote", {"planId": "plan-2", "value": "maybe"}, member["memberToken"])
        self.assertEqual(len(session["votes"]), 2)
        with self.assertRaises(APIError): self.call("/finalize", token=member["memberToken"])
        self.assertEqual(self.call("/finalize")["winningPlanId"], "plan-2")
        self.service.close()
        self.service = Service(database=self.temp.name + "/state.sqlite")
        self.assertEqual(self.call("", method="GET")["winningPlanId"], "plan-2")
    def test_context_change_invalidates_plans_and_raw_chat_not_stored(self):
        self.plan()
        state = self.call("", method="GET")
        self.assertEqual(state["context"]["selectedMessages"], [])
        changed = self.call("/context", {"participant": profile(budget=0)})
        self.assertEqual(changed["planOptions"], [])
        self.assertEqual(changed["votes"], [])
    def test_unknown_plan_and_forged_voter_rejected(self):
        self.plan()
        with self.assertRaises(APIError): self.call("/vote", {"planId": "missing", "value": "down"})
        with self.assertRaises(APIError): self.call("/vote", {"planId": "plan-1", "value": "down", "participantId": "someone"})
    def test_join_after_planning_reopens_context_collection(self):
        self.plan(); joined = self.join()
        self.assertEqual(joined["session"]["planOptions"], [])

if __name__ == "__main__": unittest.main()
