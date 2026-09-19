# PerformanceDaddy agent instructions

PerformanceDaddy is a native, local-only macOS diagnostic tool. Preserve these
boundaries:

- Diagnose from measured evidence; never invent causes or claim improvement
  without a comparable follow-up capture.
- Keep sampling read-only. Do not terminate processes, alter login items,
  change configuration, clear caches, or delete files without a separate,
  explicit reviewed action.
- Do not shell out to monitoring commands from the product. Use supported
  native macOS APIs and disclose unavailable evidence.
- Avoid privileged helpers, kernel extensions, analytics, networking, and new
  production dependencies unless repository evidence proves they are needed.
- PerformanceDaddy owns runtime diagnosis. StorageDaddy owns storage and
  configuration cleanup.
- Use XcodeBuildMCP for build, test, run, logging, and native UI verification.
- Run focused tests before the full package suite.
- Do not commit, push, sign, package, publish, or release without explicit
  owner approval.
