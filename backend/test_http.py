import json
import threading
import unittest
import urllib.request
import urllib.error
from server import make_server
from test_planner import context
from test_sessions import profile

class HTTPTests(unittest.TestCase):
    def setUp(self):
        self.server = make_server(("127.0.0.1", 0), model_call=lambda _: {"plans": []})
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True); self.thread.start()
        self.url = "http://127.0.0.1:" + str(self.server.server_port)
    def tearDown(self):
        self.server.shutdown(); self.server.server_close(); self.thread.join()
    def post(self, path, data, token=""):
        request = urllib.request.Request(self.url + path, data=json.dumps(data).encode(), headers={"Content-Type": "application/json", "Authorization": "Bearer " + token})
        try:
            with urllib.request.urlopen(request) as response: return response.status, json.load(response)
        except urllib.error.HTTPError as error: return error.code, json.load(error)
    def test_planning_endpoint_returns_three_validated_plans(self):
        status, response = self.post("/sidequest/plan", context())
        self.assertEqual(status, 200); self.assertEqual(len(response["plans"]), 3)
    def test_bad_context_is_400_and_unknown_route_is_404(self):
        self.assertEqual(self.post("/sidequest/plan", {})[0], 400)
        self.assertEqual(self.post("/missing", {})[0], 404)
    def test_two_clients_join_plan_vote_and_finalize_over_http(self):
        status, owner = self.post("/api/sessions", {"participant": profile()})
        self.assertEqual(status, 200)
        path = "/api/sessions/" + owner["session"]["id"]
        status, guest = self.post(path + "/join", {"participant": profile("Maya")}, owner["inviteToken"])
        self.assertEqual(status, 200)
        request = context(); request.pop("participants")
        status, session = self.post(path + "/plan", request, owner["memberToken"])
        self.assertEqual(status, 200); self.assertEqual(len(session["planOptions"]), 3)
        status, session = self.post(path + "/vote", {"planId": "plan-2", "value": "down"}, guest["memberToken"])
        self.assertEqual(status, 200)
        status, session = self.post(path + "/finalize", {}, owner["memberToken"])
        self.assertEqual(status, 200); self.assertEqual(session["winningPlanId"], "plan-2")
    def test_unauthorized_session_vote_is_forbidden(self):
        _, owner = self.post("/api/sessions", {"participant": profile()})
        status, _ = self.post("/api/sessions/" + owner["session"]["id"] + "/vote", {"planId": "plan-1", "value": "down"}, "invalid")
        self.assertEqual(status, 403)

if __name__ == "__main__": unittest.main()
