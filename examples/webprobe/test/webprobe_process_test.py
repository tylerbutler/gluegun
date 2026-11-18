import os
from pathlib import Path
import socket
import subprocess
import threading
import unittest
from contextlib import contextmanager


EXECUTABLE = Path(__file__).resolve().parents[1] / "dist" / "webprobe"


@contextmanager
def local_peer(response, hold_open=False):
    with socket.socket() as listener:
        listener.bind(("127.0.0.1", 0))
        listener.listen(1)
        listener.settimeout(10)
        failures = []
        release = threading.Event()

        def serve():
            try:
                with listener.accept()[0] as connection:
                    connection.settimeout(10)
                    request = b""
                    while b"\r\n\r\n" not in request:
                        chunk = connection.recv(4096)
                        if not chunk:
                            raise AssertionError("Peer closed before sending a request")
                        request += chunk
                    if response is not None:
                        connection.sendall(response)
                    if hold_open:
                        release.wait(timeout=10)
            except Exception as error:
                failures.append(error)

        thread = threading.Thread(target=serve)
        thread.start()
        try:
            yield f"http://127.0.0.1:{listener.getsockname()[1]}/"
        finally:
            release.set()
            thread.join(timeout=11)
            if thread.is_alive():
                raise AssertionError("Local peer did not stop")
            if failures:
                raise failures[0]


class WebprobeProcessTest(unittest.TestCase):
    def run_probe(self, *arguments):
        return subprocess.run(
            [str(EXECUTABLE), *arguments],
            capture_output=True,
            text=True,
            timeout=15,
            env={**os.environ, "ERL_FLAGS": "+S 2:2 +A 2"},
        )

    def assert_failure(self, arguments, message):
        result = self.run_probe(*arguments)
        self.assertNotEqual(result.returncode, 0, result)
        self.assertIn(message, result.stderr)
        self.assertNotIn("body-preview:", result.stdout)

    def test_usage_errors(self):
        cases = [
            ([], "url"),
            (["--header", "missing-colon", "http://localhost"], "Header must use"),
            (["--timeout", "-1", "http://localhost"], "Timeout must"),
            (["--timeout", "invalid", "http://localhost"], "timeout"),
            (["ftp://localhost"], "Only http:// and https://"),
            (["not-a-url"], "URL must include a host"),
        ]
        for arguments, message in cases:
            with self.subTest(arguments=arguments):
                self.assert_failure(arguments, message)

    def test_help(self):
        for flag in ["--help", "-h"]:
            with self.subTest(flag=flag):
                result = self.run_probe(flag)
                self.assertEqual(result.returncode, 0, result)
                self.assertIn("Usage:", result.stdout)
                self.assertEqual(result.stderr, "")

    def test_connection_failure(self):
        with socket.socket() as unavailable:
            unavailable.bind(("127.0.0.1", 0))
            self.assert_failure(
                ["--timeout", "100", f"http://127.0.0.1:{unavailable.getsockname()[1]}"],
                "connection failed:",
            )

    def test_request_failure(self):
        with local_peer(None) as url:
            self.assert_failure(["--timeout", "500", url], "request failed:")

    def test_request_timeout(self):
        with local_peer(None, hold_open=True) as url:
            self.assert_failure(["--timeout", "100", url], "request failed: timeout")

    def test_completed_http_responses(self):
        for status in ["200 OK", "404 Not Found", "500 Internal Server Error"]:
            with self.subTest(status=status):
                response = (
                    f"HTTP/1.1 {status}\r\nContent-Length: 2\r\n"
                    "Connection: close\r\n\r\nok"
                ).encode("ascii")
                with local_peer(response) as url:
                    result = self.run_probe("--timeout", "1000", url)
                self.assertEqual(result.returncode, 0, result)
                self.assertIn(f"status: {status[:3]}\n", result.stdout)
                self.assertIn("body-preview: ok", result.stdout)
                self.assertEqual(result.stderr, "")


if __name__ == "__main__":
    unittest.main()
