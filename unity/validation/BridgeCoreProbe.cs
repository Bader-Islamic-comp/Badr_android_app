using Companion.Presentation;

public sealed class CoreTestAvatar : IAvatarPresentation
{
    public int Calls;
    public bool Available = true;
    public bool AcceptCommands = true;
    public string[] Installed = BridgeCommand.SupportedTypes;
    public bool IsAvailable { get { return Available; } }
    public string[] Capabilities { get { return Installed; } }
    public bool Apply(BridgeCommand command) { if (!AcceptCommands) return false; Calls++; return true; }
}
