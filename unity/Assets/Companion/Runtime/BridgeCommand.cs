using System;
using System.Collections.Generic;
using System.Globalization;
using System.Text;

namespace Companion.Presentation
{
    /// <summary>
    /// What a parsed command asks the presentation layer to do.
    /// Nothing here carries text, credentials, profile data or conversation
    /// state: the envelope contract does not allow those fields to exist.
    /// </summary>
    public sealed class BridgeCommand
    {
        /// <summary>Negotiable presentation capabilities, in contract order.</summary>
        public static readonly string[] SupportedTypes = {
            "avatar.play", "avatar.set_emotion", "avatar.set_cosmetics",
            "app.pause", "app.resume"
        };

        public const string Initialize = "avatar.initialize";
        public const long MaxSequence = 9007199254740991L; // JSON-safe integer.
        public const int MaxLength = 4096;

        private static readonly string[] Animations = { "Idle", "Wave", "Nod", "Celebrate" };
        private static readonly string[] Emotions = { "neutral", "happy", "surprised" };
        private const string Character = "robert";
        private const string DefaultCosmetic = "default";

        private readonly string messageId;
        private readonly string type;
        private readonly long sequence;
        private readonly string animation;
        private readonly string emotion;
        private readonly string cosmeticId;
        private readonly string[] capabilities;

        private BridgeCommand(string messageId, string type, long sequence,
            string animation, string emotion, string cosmeticId, string[] capabilities)
        {
            this.messageId = messageId;
            this.type = type;
            this.sequence = sequence;
            this.animation = animation;
            this.emotion = emotion;
            this.cosmeticId = cosmeticId;
            this.capabilities = capabilities;
        }

        public string MessageId { get { return messageId; } }
        public string Type { get { return type; } }
        public long Sequence { get { return sequence; } }

        /// <summary>Body clip for `avatar.play`, otherwise null.</summary>
        public string Animation { get { return animation; } }

        /// <summary>Face state for `avatar.set_emotion`, otherwise null.</summary>
        public string Emotion { get { return emotion; } }

        /// <summary>Allowlisted cosmetic for `avatar.set_cosmetics`, otherwise null.</summary>
        public string CosmeticId { get { return cosmeticId; } }

        /// <summary>Requested capabilities for `avatar.initialize`, otherwise null.</summary>
        public string[] Capabilities { get { return capabilities; } }

        /// <summary>Initialization and equipment are state changing and acknowledged.</summary>
        public bool RequiresAcknowledgement
        {
            get { return type == Initialize || type == "avatar.set_cosmetics"; }
        }

        public static bool IsSupportedType(string value)
        {
            return Array.IndexOf(SupportedTypes, value) >= 0;
        }

        /// <summary>
        /// Strict allowlist parse. Anything unexpected — an extra or duplicate
        /// field, an unknown command, a malformed UUID, a fractional or
        /// out-of-range sequence, or any field carrying free text — fails here,
        /// before the presentation layer is touched.
        /// </summary>
        public static BridgeCommand Parse(string message)
        {
            if (message == null || message.Length == 0 || message.Length > MaxLength) return null;
            JsonValue root = Json.Parse(message);
            if (root == null || root.Kind != JsonKind.Object || root.Members.Count != 5) return null;

            JsonValue version = Member(root, "schemaVersion");
            JsonValue id = Member(root, "messageId");
            JsonValue kind = Member(root, "type");
            JsonValue order = Member(root, "sequence");
            JsonValue payload = Member(root, "payload");
            if (version == null || id == null || kind == null || order == null || payload == null) return null;

            long parsedVersion;
            if (!version.TryInteger(out parsedVersion) || parsedVersion != 1) return null;
            if (id.Kind != JsonKind.String || !IsUuid(id.Text)) return null;
            if (kind.Kind != JsonKind.String) return null;
            long parsedSequence;
            if (!order.TryInteger(out parsedSequence)) return null;
            if (parsedSequence < 0 || parsedSequence > MaxSequence) return null;
            if (payload.Kind != JsonKind.Object) return null;

            string commandType = kind.Text;
            if (commandType == Initialize)
            {
                if (payload.Members.Count != 2) return null;
                JsonValue characterId = Member(payload, "characterId");
                JsonValue requested = Member(payload, "capabilities");
                if (characterId == null || requested == null) return null;
                if (characterId.Kind != JsonKind.String || characterId.Text != Character) return null;
                if (requested.Kind != JsonKind.Array || requested.Items.Count > SupportedTypes.Length) return null;
                List<string> names = new List<string>();
                for (int i = 0; i < requested.Items.Count; i++)
                {
                    JsonValue item = requested.Items[i];
                    if (item.Kind != JsonKind.String || !IsSupportedType(item.Text)) return null;
                    if (names.Contains(item.Text)) return null;
                    names.Add(item.Text);
                }
                return new BridgeCommand(id.Text, commandType, parsedSequence, null, null, null, names.ToArray());
            }

            if (commandType == "avatar.play")
            {
                string value = SingleString(payload, "animation", Animations);
                if (value == null) return null;
                return new BridgeCommand(id.Text, commandType, parsedSequence, value, null, null, null);
            }

            if (commandType == "avatar.set_emotion")
            {
                string value = SingleString(payload, "emotion", Emotions);
                if (value == null) return null;
                return new BridgeCommand(id.Text, commandType, parsedSequence, null, value, null, null);
            }

            if (commandType == "avatar.set_cosmetics")
            {
                string value = SingleString(payload, "cosmeticId", new string[] { DefaultCosmetic });
                if (value == null) return null;
                return new BridgeCommand(id.Text, commandType, parsedSequence, null, null, value, null);
            }

            if (commandType == "app.pause" || commandType == "app.resume")
            {
                if (payload.Members.Count != 0) return null;
                return new BridgeCommand(id.Text, commandType, parsedSequence, null, null, null, null);
            }

            return null;
        }

        private static JsonValue Member(JsonValue value, string name)
        {
            JsonValue result;
            return value.Members.TryGetValue(name, out result) ? result : null;
        }

        private static string SingleString(JsonValue payload, string name, string[] allowed)
        {
            if (payload.Members.Count != 1) return null;
            JsonValue value = Member(payload, name);
            if (value == null || value.Kind != JsonKind.String) return null;
            return Array.IndexOf(allowed, value.Text) >= 0 ? value.Text : null;
        }

        private static bool IsUuid(string value)
        {
            if (value == null || value.Length != 36) return false;
            for (int i = 0; i < value.Length; i++)
            {
                char character = value[i];
                if (i == 8 || i == 13 || i == 18 || i == 23)
                {
                    if (character != '-') return false;
                }
                else if (!Uri.IsHexDigit(character))
                {
                    return false;
                }
            }
            return true;
        }
    }

    /// <summary>The presentation surface a session is allowed to drive.</summary>
    public interface IAvatarPresentation
    {
        /// <summary>False when required presentation assets are missing.</summary>
        bool IsAvailable { get; }

        /// <summary>Capabilities actually installed in this room.</summary>
        string[] Capabilities { get; }

        /// <summary>Applies a validated command. False means it was not performed.</summary>
        bool Apply(BridgeCommand command);
    }

    /// <summary>The outcome of one received envelope.</summary>
    public sealed class BridgeResult
    {
        private readonly bool accepted;
        private readonly string reason;
        private readonly bool needsAcknowledgement;

        public BridgeResult(bool accepted, string reason, bool needsAcknowledgement)
        {
            this.accepted = accepted;
            this.reason = reason;
            this.needsAcknowledgement = needsAcknowledgement;
        }

        public bool Accepted { get { return accepted; } }

        /// <summary>One of the contract's `bridge.ack` reasons.</summary>
        public string Reason { get { return reason; } }

        /// <summary>True when the sender is waiting for a `bridge.ack`.</summary>
        public bool NeedsAcknowledgement { get { return needsAcknowledgement; } }
    }

    internal enum JsonKind { Object, Array, String, Number, Boolean, Null }

    internal sealed class JsonValue
    {
        public JsonKind Kind;
        public string Text;
        public bool Boolean;
        public bool IsInteger;
        public Dictionary<string, JsonValue> Members;
        public List<JsonValue> Items;

        public bool TryInteger(out long value)
        {
            value = 0;
            if (Kind != JsonKind.Number || !IsInteger) return false;
            return long.TryParse(Text, NumberStyles.AllowLeadingSign,
                CultureInfo.InvariantCulture, out value);
        }
    }

    /// <summary>
    /// A small strict JSON reader. It exists so the session core stays free of
    /// engine and third-party dependencies and can be compiled and exercised
    /// outside Unity. Duplicate keys, trailing content and unescaped control
    /// characters are errors rather than tolerated input.
    /// </summary>
    internal static class Json
    {
        private const int MaxDepth = 8;

        public static JsonValue Parse(string text)
        {
            int index = 0;
            JsonValue value = ParseValue(text, ref index, 0);
            if (value == null) return null;
            SkipWhitespace(text, ref index);
            return index == text.Length ? value : null;
        }

        private static JsonValue ParseValue(string text, ref int index, int depth)
        {
            if (depth > MaxDepth) return null;
            SkipWhitespace(text, ref index);
            if (index >= text.Length) return null;
            char character = text[index];
            if (character == '{') return ParseObject(text, ref index, depth);
            if (character == '[') return ParseArray(text, ref index, depth);
            if (character == '"')
            {
                string parsed = ParseString(text, ref index);
                if (parsed == null) return null;
                JsonValue value = new JsonValue();
                value.Kind = JsonKind.String;
                value.Text = parsed;
                return value;
            }
            if (Literal(text, ref index, "true")) return Boolean(true);
            if (Literal(text, ref index, "false")) return Boolean(false);
            if (Literal(text, ref index, "null"))
            {
                JsonValue value = new JsonValue();
                value.Kind = JsonKind.Null;
                return value;
            }
            return ParseNumber(text, ref index);
        }

        private static JsonValue Boolean(bool state)
        {
            JsonValue value = new JsonValue();
            value.Kind = JsonKind.Boolean;
            value.Boolean = state;
            return value;
        }

        private static bool Literal(string text, ref int index, string literal)
        {
            if (index + literal.Length > text.Length) return false;
            if (string.CompareOrdinal(text, index, literal, 0, literal.Length) != 0) return false;
            index += literal.Length;
            return true;
        }

        private static JsonValue ParseObject(string text, ref int index, int depth)
        {
            index++; // '{'
            JsonValue value = new JsonValue();
            value.Kind = JsonKind.Object;
            value.Members = new Dictionary<string, JsonValue>(StringComparer.Ordinal);
            SkipWhitespace(text, ref index);
            if (index < text.Length && text[index] == '}') { index++; return value; }
            while (true)
            {
                SkipWhitespace(text, ref index);
                if (index >= text.Length || text[index] != '"') return null;
                string name = ParseString(text, ref index);
                if (name == null || value.Members.ContainsKey(name)) return null;
                SkipWhitespace(text, ref index);
                if (index >= text.Length || text[index] != ':') return null;
                index++;
                JsonValue member = ParseValue(text, ref index, depth + 1);
                if (member == null) return null;
                value.Members.Add(name, member);
                SkipWhitespace(text, ref index);
                if (index >= text.Length) return null;
                if (text[index] == ',') { index++; continue; }
                if (text[index] == '}') { index++; return value; }
                return null;
            }
        }

        private static JsonValue ParseArray(string text, ref int index, int depth)
        {
            index++; // '['
            JsonValue value = new JsonValue();
            value.Kind = JsonKind.Array;
            value.Items = new List<JsonValue>();
            SkipWhitespace(text, ref index);
            if (index < text.Length && text[index] == ']') { index++; return value; }
            while (true)
            {
                JsonValue item = ParseValue(text, ref index, depth + 1);
                if (item == null) return null;
                value.Items.Add(item);
                SkipWhitespace(text, ref index);
                if (index >= text.Length) return null;
                if (text[index] == ',') { index++; continue; }
                if (text[index] == ']') { index++; return value; }
                return null;
            }
        }

        private static string ParseString(string text, ref int index)
        {
            index++; // opening quote
            StringBuilder builder = new StringBuilder();
            while (index < text.Length)
            {
                char character = text[index++];
                if (character == '"') return builder.ToString();
                if (character < ' ') return null;
                if (character != '\\') { builder.Append(character); continue; }
                if (index >= text.Length) return null;
                char escape = text[index++];
                switch (escape)
                {
                    case '"': builder.Append('"'); break;
                    case '\\': builder.Append('\\'); break;
                    case '/': builder.Append('/'); break;
                    case 'b': builder.Append('\b'); break;
                    case 'f': builder.Append('\f'); break;
                    case 'n': builder.Append('\n'); break;
                    case 'r': builder.Append('\r'); break;
                    case 't': builder.Append('\t'); break;
                    case 'u':
                        if (index + 4 > text.Length) return null;
                        int code;
                        if (!int.TryParse(text.Substring(index, 4), NumberStyles.HexNumber,
                                CultureInfo.InvariantCulture, out code)) return null;
                        builder.Append((char)code);
                        index += 4;
                        break;
                    default: return null;
                }
            }
            return null;
        }

        private static JsonValue ParseNumber(string text, ref int index)
        {
            int start = index;
            if (index < text.Length && text[index] == '-') index++;
            if (index >= text.Length || !IsDigit(text[index])) return null;
            if (text[index] == '0') index++;
            else while (index < text.Length && IsDigit(text[index])) index++;
            bool integer = true;
            if (index < text.Length && text[index] == '.')
            {
                integer = false;
                index++;
                if (index >= text.Length || !IsDigit(text[index])) return null;
                while (index < text.Length && IsDigit(text[index])) index++;
            }
            if (index < text.Length && (text[index] == 'e' || text[index] == 'E'))
            {
                integer = false;
                index++;
                if (index < text.Length && (text[index] == '+' || text[index] == '-')) index++;
                if (index >= text.Length || !IsDigit(text[index])) return null;
                while (index < text.Length && IsDigit(text[index])) index++;
            }
            JsonValue value = new JsonValue();
            value.Kind = JsonKind.Number;
            value.Text = text.Substring(start, index - start);
            value.IsInteger = integer;
            return value;
        }

        private static bool IsDigit(char character)
        {
            return character >= '0' && character <= '9';
        }

        private static void SkipWhitespace(string text, ref int index)
        {
            while (index < text.Length)
            {
                char character = text[index];
                if (character == ' ' || character == '\t' || character == '\n' || character == '\r') index++;
                else return;
            }
        }
    }
}
