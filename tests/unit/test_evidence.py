from __future__ import annotations

from scripts.summarize_evidence import result_counts


def test_result_counts_fail_closed() -> None:
    passed, failed = result_counts(
        {"controls": [{"status": "pass"}, {"status": "fail"}, {"status": "unknown"}]}
    )
    assert passed == 1
    assert failed == 2
