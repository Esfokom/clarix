param(
  [string]$Device = 'windows'
)

$ErrorActionPreference = 'Stop'

flutter drive -d $Device --profile `
  --driver test_driver/phase1_editing_test.dart `
  --target integration_test/live_editing_round_trip_test.dart
