TLSF for Unikraft
=================

This is the port of the TLSF [0] general-purpose memory allocator for Unikraft
as an external library.

[0] http://www.gii.upv.es/tlsf/

LROS note: copied from https://github.com/unikraft/lib-tlsf
(staging, commit 8f00ced4a9651334b6feef06c585a79c9e4333b8) instead of a
submodule since it needed LROS-specific changes anyway: addmem support
(chunked, gap pages against area merging), locking, a large-alloc guard,
availmem statistics, and patch 04 (no memset of demand-paged areas).
TLSF 2.4.6 itself is fetched at build time, not committed.
