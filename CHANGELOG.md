# Changelog

## [0.9.0] - 2025-09-15
### Added
- Two-week view (Mon–Sun) with always-visible wallboard columns.
- Kiosk simplified signup flow with roster dropdown & confirmation.
- Admin week lifecycle: draft → publish → close; can save draft without publishing.
- Weekend freeze: Sat/Sun signups close at Friday 15:30 (configurable TZ).
- Day vs Rotating shift priority integrated with existing seniority rules.
- SMS notifications (Twilio) on assignment/bump (gated by TWILIO_ENABLED).

### Changed
- Wallboard gains focus toggle (bold) but displays both weeks simultaneously.

### Fixed
- Deterministic tiebreakers for edge cases.
