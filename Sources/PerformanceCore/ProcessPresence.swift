import NativeInspection

public enum ProcessPresence: Int, Sendable {
    case unknown = -1, gone = 0, observed = 1
    public static func inspect(_ identity: ProcessIdentity) -> Self {
        Self(rawValue: Int(pd_presence(identity.pid, identity.started))) ?? .unknown
    }
}
