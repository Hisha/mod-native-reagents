#!/usr/bin/env python3
"""Behavioral model for the atomic paged client synchronization contract."""

class SyncClient:
    def __init__(self):
        self.serial = 0
        self.active = None
        self.items = {99: 1}
        self.status = "ready"

    def start(self, retry=0):
        self.serial += 1
        self.active = {"id": self.serial, "total": None, "pages": {}, "retry": retry}
        self.status = "loading"
        return self.serial

    def page(self, sync_id, index, total, rows):
        if not self.active or sync_id != self.active["id"] or total < 1 or index >= total:
            return False
        if self.active["total"] not in (None, total):
            return False
        self.active["total"] = total
        self.active["pages"][index] = dict(rows)  # duplicate replaces, never adds
        if len(self.active["pages"]) != total or any(i not in self.active["pages"] for i in range(total)):
            return False
        combined = {}
        for page in range(total): combined.update(self.active["pages"][page])
        self.items, self.active, self.status = combined, None, "ready"
        return True

    def timeout(self):
        retry = self.active["retry"] if self.active else 2
        if retry < 2: return self.start(retry + 1)
        self.active, self.status = None, "failed"
        return None

    def server_unavailable(self):
        self.active, self.status = None, "unavailable"


def main():
    c = SyncClient()
    first = c.start()
    assert c.items == {99: 1}  # atomic: prior snapshot remains visible
    assert c.page(first, 0, 1, {1: 10}) and c.items == {1: 10}

    second = c.start()
    assert not c.page(second, 2, 3, {3: 30})  # out of order retained
    assert not c.page(second, 0, 3, {1: 10})
    assert not c.page(second, 0, 3, {1: 11})  # duplicate replaces page
    assert c.page(second, 1, 3, {2: 20})
    assert c.items == {1: 11, 2: 20, 3: 30}

    stale = c.start()
    current = c.start()
    assert not c.page(stale, 0, 1, {7: 7})
    assert c.page(current, 0, 1, {8: 8}) and c.items == {8: 8}

    missing = c.start()
    assert not c.page(missing, 0, 2, {1: 1})
    retry1 = c.timeout(); assert retry1 != missing and c.status == "loading"
    retry2 = c.timeout(); assert retry2 != retry1 and c.status == "loading"
    assert c.timeout() is None and c.status == "failed" and c.items == {8: 8}
    c.server_unavailable(); assert c.status == "unavailable" and c.items == {8: 8}
    print("PASS synchronization single/multi page, duplicate/out-of-order/stale, timeout/retry, unavailable, atomic publish")

if __name__ == "__main__": main()
