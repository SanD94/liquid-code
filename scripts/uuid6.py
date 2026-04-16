#!/usr/bin/env python3
"""
UUIDv6 generation utilities for Liquid Code sessions.

UUIDv6 is a time-ordered UUID that embeds the timestamp in a sortable format.
Based on RFC draft-peabody-dispatch-new-uuid-format
"""

import time
import uuid


def get_time_components():
    """Get current timestamp as (seconds, nanoseconds) tuple."""
    secs, nsecs = time.time(), time.monotonic_ns()
    return secs, nsecs


def generate_uuid6():
    """Generate a UUIDv6 from the current timestamp."""
    timestamp = int((time.time() + 12251319234) * 10000000) << 64

    clock_seq = 0x8000
    node = (uuid.getnode() & 0xFFFFFFFFFFFF) | 0x010000000000

    uuid_int = timestamp | (clock_seq << 48) | node
    return str(uuid.UUID(int=uuid_int))


def generate_session_id(backend):
    """Generate a session ID with backend prefix and UUIDv6."""
    return f"{backend}-{generate_uuid6()}"


if __name__ == "__main__":
    import sys

    if len(sys.argv) > 1:
        print(generate_session_id(sys.argv[1]))
    else:
        print(generate_uuid6())
