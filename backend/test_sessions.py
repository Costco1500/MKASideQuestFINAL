import json
import tempfile
import unittest
from concurrent.futures import ThreadPoolExecutor
from unittest.mock import Mock
from server import Service, APIError
from planner import demo_plans
from test_planner import context


def profile(name="Alex", budget=15):
    return {"id": "client-cannot-choose", "displayName": name, "ageRange": "18–20", "maxBudget": budget,
            "approximateArea": "Midtown", "availability": {"start": "2026-10-01T17:00:00Z", "end": "2026-10-01T22:00:00Z"},
            "busyIntervals": [], "calendarConnectionStatus": "manual"}


class SessionTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.model = Mock(side_effect=lambda request: {"plans": demo_plans(request)})
        self.service = Service(database=self.temp.name + "/state.sqlite", model_call=self.model)
        self.owner = self.service.dispatch("POST", "/api/sessions", {"expectedParticipantCount": 2}, "")
        self.path = "/api/sessions/" + self.owner["session"]["id"]

    def tearDown(self):
        self.service.close()
        self.temp.cleanup()

    def call(self, suffix, body=None, token=None, method="POST"):
        return self.service.dispatch(method, self.path + suffix, body or {}, token or self.owner["memberToken"])

    def complete_owner(self):
        return self.call("/context", {"participant": profile()})

    def join(self):
        return self.call("/join", {"participant": profile("Maya")}, self.owner["inviteToken"])

    def ready_session(self):
        self.complete_owner()
        return self.join()

    def plan(self):
        request = context()
        return self.call("/plan", {"selectedMessages": request["selectedMessages"], "candidateTimeWindows": request["candidateTimeWindows"], "timeZone": "UTC"})

    def test_invitation_exists_before_organizer_profile(self):
        session = self.owner["session"]
        self.assertEqual(session["expectedParticipantCount"], 2)
        self.assertEqual(session["participants"], [])
        self.assertEqual(session["readyParticipantIds"], [])
        self.assertTrue(self.owner["isOwner"])
        self.assertTrue(self.owner["memberToken"])
        self.assertEqual(self.call("", token=self.owner["inviteToken"], method="GET"), session)

    def test_plan_waits_for_organizer_and_absent_invitees_without_calling_model(self):
        for finish_context in [lambda: None, self.complete_owner]:
            finish_context()
            with self.assertRaises(APIError) as error:
                self.plan()
            self.assertEqual(error.exception.status, 409)
        self.model.assert_not_called()
        state = self.call("", method="GET")
        self.assertEqual(state["readyParticipantIds"], [self.owner["participantId"]])

    def test_final_done_unlocks_exactly_one_model_call_with_selected_text_only(self):
        member = self.join()
        with self.assertRaises(APIError) as error:
            self.plan()
        self.assertEqual(error.exception.status, 409)
        self.model.assert_not_called()
        completed = self.complete_owner()
        self.assertCountEqual(completed["readyParticipantIds"], [self.owner["participantId"], member["participantId"]])
        planned = self.plan()
        self.assertEqual(planned["source"], "ai")
        self.assertEqual(len(planned["planOptions"]), 3)
        self.model.assert_called_once()
        request = self.model.call_args.args[0]
        self.assertEqual(set(request), {"participants", "selectedMessages", "candidateTimeWindows", "timeZone"})
        self.assertEqual(request["selectedMessages"], context()["selectedMessages"])
        self.assertCountEqual([person["id"] for person in request["participants"]], completed["readyParticipantIds"])
        stored = self.service.db.execute("SELECT state FROM sessions WHERE id=?", (planned["id"],)).fetchone()[0]
        self.assertNotIn("Quiet, please", stored)
        self.assertEqual(json.loads(stored)["context"]["selectedMessages"], [])

    def test_invalid_expected_count_and_unbounded_legacy_creation_are_rejected(self):
        for value in [0, 13, -1, 2.5, True, "2", None]:
            with self.subTest(count=value), self.assertRaises(APIError) as error:
                self.service.dispatch("POST", "/api/sessions", {"expectedParticipantCount": value}, "")
            self.assertEqual(error.exception.status, 400)
        with self.assertRaises(APIError):
            self.service.dispatch("POST", "/api/sessions", {"participant": profile()}, "")
        for count in [1, 12]:
            created = self.service.dispatch("POST", "/api/sessions", {"expectedParticipantCount": count}, "")
            self.assertEqual(created["session"]["expectedParticipantCount"], count)

    def test_readiness_cannot_be_spoofed_on_create_join_context_or_plan(self):
        with self.assertRaises(APIError):
            self.service.dispatch("POST", "/api/sessions", {"expectedParticipantCount": 2, "readyParticipantIds": ["fake"]}, "")
        with self.assertRaises(APIError):
            self.call("/join", {"participant": profile("Maya"), "readyParticipantIds": ["fake"]}, self.owner["inviteToken"])
        with self.assertRaises(APIError):
            self.call("/context", {"participant": profile(), "readyParticipantIds": ["fake"]})
        self.ready_session()
        request = context(); request.pop("participants"); request["readyParticipantIds"] = ["fake"]
        with self.assertRaises(APIError):
            self.call("/plan", request)
        self.model.assert_not_called()

    def test_invalid_profile_does_not_take_slot_or_mark_done(self):
        invalid = profile(); invalid["displayName"] = ""
        with self.assertRaises(APIError):
            self.call("/context", {"participant": invalid})
        with self.assertRaises(APIError):
            self.call("/join", {"participant": invalid}, self.owner["inviteToken"])
        state = self.call("", method="GET")
        self.assertEqual(state["participants"], [])
        self.assertEqual(state["readyParticipantIds"], [])
        self.assertEqual(self.service.db.execute("SELECT COUNT(*) FROM members").fetchone()[0], 1)
        self.join()

    def test_pending_organizer_counts_toward_roster_capacity(self):
        self.join()
        with self.assertRaises(APIError) as error:
            self.call("/join", {"participant": profile("Jake")}, self.owner["inviteToken"])
        self.assertEqual(error.exception.status, 409)
        self.assertEqual(len(self.call("", method="GET")["participants"]), 1)

    def test_join_authentication_and_own_context_only(self):
        member = self.ready_session()
        self.assertEqual(len(member["session"]["participants"]), 2)
        self.assertNotEqual(member["participantId"], "client-cannot-choose")
        with self.assertRaises(APIError): self.call("", token="bad-token", method="GET")
        updated = self.call("/context", {"participant": profile("Maya", 0)}, member["memberToken"])
        self.assertEqual(updated["participants"][0]["maxBudget"], 15)
        self.assertEqual(updated["participants"][1]["maxBudget"], 0)
        self.assertEqual(len(updated["readyParticipantIds"]), 2)

    def test_multimember_votes_upsert_and_finalize_survive_restart(self):
        member = self.ready_session(); self.plan()
        with ThreadPoolExecutor() as pool:
            list(pool.map(lambda token: self.call("/vote", {"planId": "plan-2", "value": "down"}, token), [member["memberToken"], self.owner["memberToken"]]))
        session = self.call("/vote", {"planId": "plan-2", "value": "maybe"}, member["memberToken"])
        self.assertEqual(len(session["votes"]), 2)
        with self.assertRaises(APIError): self.call("/finalize", token=member["memberToken"])
        self.assertEqual(self.call("/finalize")["winningPlanId"], "plan-2")
        self.service.close()
        self.service = Service(database=self.temp.name + "/state.sqlite")
        restarted = self.call("", method="GET")
        self.assertEqual(restarted["winningPlanId"], "plan-2")
        self.assertEqual(len(restarted["readyParticipantIds"]), 2)

    def test_context_change_invalidates_plans_and_raw_chat_not_stored(self):
        self.ready_session(); self.plan()
        self.call("/vote", {"planId": "plan-2", "value": "down"})
        self.call("/finalize")
        state = self.call("", method="GET")
        self.assertEqual(state["context"]["selectedMessages"], [])
        changed = self.call("/context", {"participant": profile(budget=0)})
        self.assertEqual(changed["planOptions"], [])
        self.assertEqual(changed["votes"], [])
        self.assertIsNone(changed["winningPlanId"])
        self.assertIsNone(changed["context"])
        self.assertEqual(len(changed["readyParticipantIds"]), 2)

    def test_context_change_during_planning_rejects_stale_result(self):
        self.ready_session()
        def update_during_model(request):
            self.call("/context", {"participant": profile(budget=0)})
            return {"plans": demo_plans(request)}
        self.model.side_effect = update_during_model
        with self.assertRaises(APIError) as error:
            self.plan()
        self.assertEqual(error.exception.status, 409)
        self.assertEqual(self.call("", method="GET")["planOptions"], [])

    def test_unknown_plan_and_forged_voter_rejected(self):
        self.ready_session(); self.plan()
        with self.assertRaises(APIError): self.call("/vote", {"planId": "missing", "value": "down"})
        with self.assertRaises(APIError): self.call("/vote", {"planId": "plan-1", "value": "down", "participantId": "someone"})

    def test_full_roster_rejects_late_join_without_invalidating_poll(self):
        self.ready_session(); planned = self.plan()
        with self.assertRaises(APIError) as error:
            self.join()
        self.assertEqual(error.exception.status, 409)
        self.assertEqual(self.call("", method="GET")["planOptions"], planned["planOptions"])

    def test_invites_are_read_only_members_cannot_plan_and_expired_sessions_close(self):
        member = self.ready_session()
        with self.assertRaises(APIError) as error:
            self.call("/vote", {"planId": "plan-1", "value": "down"}, self.owner["inviteToken"])
        self.assertEqual(error.exception.status, 403)
        with self.assertRaises(APIError) as error:
            self.call("/plan", token=member["memberToken"])
        self.assertEqual(error.exception.status, 403)
        with self.assertRaises(APIError) as error:
            self.call("/vote", method="DELETE")
        self.assertEqual(error.exception.status, 404)
        self.service.db.execute("UPDATE sessions SET expires=0"); self.service.db.commit()
        with self.assertRaises(APIError) as error: self.call("", method="GET")
        self.assertEqual(error.exception.status, 404)


if __name__ == "__main__": unittest.main()
