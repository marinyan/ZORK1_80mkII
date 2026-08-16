using System.Text;
using System.Text.Encodings.Web;
using System.Text.Json;

namespace Zork1Japanese;

internal interface ITranslatedInputObserver
{
    void InputTranslated(string rawInput, string translatedInput, string zMachineInput);
}

internal sealed class SessionLogHost : IZMachineHost, ITranslatedInputObserver, IDisposable
{
    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        Encoder = JavaScriptEncoder.UnsafeRelaxedJsonEscaping
    };

    private readonly IZMachineHost _inner;
    private readonly StreamWriter _writer;
    private readonly StringBuilder _pendingOutput = new();
    private int _sequence;
    private int _turn;
    private string? _pendingRawInput;
    private bool _disposed;

    public SessionLogHost(
        IZMachineHost inner,
        string logDirectory,
        string portVersion,
        string edition,
        string language,
        bool sourceEnglish)
    {
        _inner = inner;
        logDirectory = Path.GetFullPath(logDirectory);
        Directory.CreateDirectory(logDirectory);
        var startedAt = DateTimeOffset.Now;
        var sessionId = Guid.NewGuid().ToString("N");
        FilePath = Path.Combine(
            logDirectory,
            $"zork-session-{startedAt:yyyyMMdd-HHmmss-fff}-{Environment.ProcessId}.jsonl");
        _writer = new StreamWriter(FilePath, false, new UTF8Encoding(false));
        WriteEvent(new
        {
            type = "session",
            sequence = NextSequence(),
            schemaVersion = 1,
            sessionId,
            startedAt,
            portVersion,
            edition,
            language,
            sourceEnglish
        });
    }

    public string FilePath { get; }

    public void Write(string text)
    {
        _inner.Write(text);
        _pendingOutput.Append(text);
    }

    public string? ReadLine()
    {
        FlushOutput();
        var input = _inner.ReadLine();
        _pendingRawInput = input;
        return input;
    }

    public void InputTranslated(string rawInput, string translatedInput, string zMachineInput)
    {
        _pendingRawInput = null;
        var hasJapanese = ContainsJapanese(rawInput);
        var hasAsciiLetters = rawInput.Any(character =>
            character is >= 'a' and <= 'z' or >= 'A' and <= 'Z');
        var inputKind = hasJapanese
            ? hasAsciiLetters ? "mixed" : "japanese"
            : hasAsciiLetters ? "english" : "other";

        WriteEvent(new
        {
            type = "input",
            sequence = NextSequence(),
            turn = ++_turn,
            at = DateTimeOffset.Now,
            rawInput,
            translatedInput,
            zMachineInput,
            inputKind,
            translationApplied = !rawInput.Equals(translatedInput, StringComparison.OrdinalIgnoreCase)
        });
    }

    public void Dispose()
    {
        if (_disposed)
            return;
        _disposed = true;
        if (_pendingRawInput is { } rawInput)
            InputTranslated(rawInput, rawInput, rawInput);
        FlushOutput();
        WriteEvent(new
        {
            type = "session-end",
            sequence = NextSequence(),
            endedAt = DateTimeOffset.Now,
            turns = _turn
        });
        _writer.Dispose();
    }

    private void FlushOutput()
    {
        if (_pendingOutput.Length == 0)
            return;
        var text = _pendingOutput.ToString();
        _pendingOutput.Clear();
        WriteEvent(new
        {
            type = "output",
            sequence = NextSequence(),
            at = DateTimeOffset.Now,
            text
        });
    }

    private void WriteEvent(object value)
    {
        _writer.WriteLine(JsonSerializer.Serialize(value, JsonOptions));
        _writer.Flush();
    }

    private int NextSequence() => ++_sequence;

    private static bool ContainsJapanese(string value)
    {
        foreach (var rune in value.EnumerateRunes())
        {
            if (rune.Value is >= 0x3040 and <= 0x30ff or
                >= 0x3400 and <= 0x4dbf or
                >= 0x4e00 and <= 0x9fff or
                >= 0xff66 and <= 0xff9f)
                return true;
        }
        return false;
    }
}
