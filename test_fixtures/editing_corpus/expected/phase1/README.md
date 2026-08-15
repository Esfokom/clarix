# Phase 1 native-text expectations

Phase 1 permits native materialization only when a text object has a deterministic
source occurrence, confidence `1.0`, a valid embeddable font reference, and a
source-glyph map covering every replacement character. The generated Latin case
is used to verify searchable round-trip replacement through this contract.

Subset, embedded, rotated, mixed-content, and form cases remain fail-closed until
their font bytes, source operators, clipping, and unaffected-region raster checks
are independently qualified. Tests store hashes and tolerances only; private font
bytes remain outside this directory.
