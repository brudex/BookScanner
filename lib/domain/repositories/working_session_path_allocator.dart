/// Domain-facing abstraction over scratch-file storage for one ephemeral,
/// unpersisted multi-source page-composition session (SPEC 6.5 "editing").
/// Deliberately separate from [PagePathAllocator]: that interface is keyed
/// to permanent, DB-backed page/export identities, while this one is keyed
/// to a transient session that exists only in memory in a ViewModel and is
/// wiped in bulk on dispose/cancel — extending [PagePathAllocator] instead
/// would force every one of its several existing implementers (production
/// and test fakes) to grow a method that doesn't fit their actual job.
abstract interface class WorkingSessionPathAllocator {
  String pagePathFor(String sessionId, String pageId, {required String ext});

  /// Deletes every scratch file for [sessionId]. Idempotent.
  Future<void> clearSession(String sessionId);
}
