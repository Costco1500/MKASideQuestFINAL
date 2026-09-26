import json
import threading
import unittest
import urllib.request
import urllib.error
from server import make_server
from test_planner import context

class HTTPTests(unittest.TestCase):
    def setUp(self):
        self.server = make_server(("127.0.0.1", 0), model_call=lambda _: {"plans": []})
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True); self.thread.start()
        self.url = "http://127.0.0.1:" + str(self.server.server_port)
    def tearDown(self):
        self.server.shutdown(); self.server.server_close(); self.thread.join()
    def post(self, path, data):
        request = urllib.request.Request(self.url + path, data=json.dumps(data).encode(), headers={"Content-Type": "application/json"})
        try:
            with urllib.request.urlopen(request) as response: return response.status, json.load(response)
        except urllib.error.HTTPError as error: return error.code, json.load(error)
    def test_planning_endpoint_returns_three_validated_plans(self):
        status, response = self.post("/sidequest/plan", context())
        self.assertEqual(status, 200); self.assertEqual(len(response["plans"]), 3)
    def test_bad_context_is_400_and_unknown_route_is_404(self):
        self.assertEqual(self.post("/sidequest/plan", {})[0], 400)
        self.assertEqual(self.post("/missing", {})[0], 404)

if __name__ == "__main__": unittest.main()
