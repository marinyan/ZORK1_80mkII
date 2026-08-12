using System.Reflection;
using System.Text;

namespace Zork1Japanese;

internal static class Program
{
    private static int Main(string[] args)
    {
        Console.InputEncoding = Encoding.UTF8;
        Console.OutputEncoding = Encoding.UTF8;

        try
        {
            var assembly = Assembly.GetExecutingAssembly();
            var portVersion = assembly
                .GetCustomAttribute<AssemblyInformationalVersionAttribute>()?
                .InformationalVersion ?? assembly.GetName().Version?.ToString(3) ?? "0.0.0";
            if (args.Contains("--version", StringComparer.OrdinalIgnoreCase))
            {
                Console.WriteLine(portVersion);
                return 0;
            }
            var story = ReadResource(assembly, "Zork1Japanese.zork1.z3");
            var english = args.Contains("--english", StringComparer.OrdinalIgnoreCase);
            var catalogReport = args.Contains("--catalog-report", StringComparer.OrdinalIgnoreCase);
            var languageDirectory = ResolveLanguageDirectory(args);
            var catalog = !english || catalogReport
                ? TranslationCatalog.Load(languageDirectory)
                : null;

            var inputToTranslate = OptionValue(args, "--translate-input");
            if (inputToTranslate is not null)
            {
                if (catalog is null)
                    throw new ArgumentException("--translate-input cannot be combined with --english.");
                Console.WriteLine(catalog.TranslateInput(inputToTranslate));
                return 0;
            }

            var outputLineToTranslate = OptionValue(args, "--translate-output-line");
            if (outputLineToTranslate is not null)
            {
                if (catalog is null)
                    throw new ArgumentException("--translate-output-line cannot be combined with --english.");
                Console.WriteLine(catalog.TranslateOutputLine(outputLineToTranslate));
                return 0;
            }

            if (catalogReport)
            {
                Console.WriteLine($"言語パック: {languageDirectory}");
                Console.WriteLine(catalog!.Report());
                return 0;
            }

            var smoke = args.Contains("--smoke", StringComparer.OrdinalIgnoreCase);
            var smokeCommands = SplitLines(catalog?.Ui(
                "smoke.commands",
                "look\nopen mailbox\ntake leaflet\nread leaflet\nnorth\neast\nopen window\nenter\nlook\nwest\nlook\ntake lamp\nlight lamp\ninventory\nquit\nyes") ?? "");
            IZMachineHost host = smoke
                ? new ScriptHost(smokeCommands)
                : new ConsoleHost();
            host.Write(catalog?.FormatUi(
                "port.version",
                "Windows port version {0}\n",
                portVersion) ?? $"Windows port version {portVersion}\n");

            var machine = new ZMachine(story, host, catalog);
            machine.Run(smoke ? 2_000_000 : int.MaxValue);

            if (smoke)
            {
                var output = ((ScriptHost)host).Output;
                Console.Write(output);
                var expectations = SplitLines(catalog?.Ui(
                    "smoke.expected",
                    "West of House\nmailbox\nleaflet\nKitchen\nLiving Room\nlamp") ?? "");
                foreach (var expectation in expectations)
                {
                    if (output.Contains(expectation, StringComparison.Ordinal))
                        continue;
                    Console.Error.WriteLine($"スモークテスト: 出力に必要な文字列がない: {expectation}");
                    return 2;
                }
                var unexpected = SplitLines(catalog?.Ui("smoke.unexpected", "") ?? "");
                foreach (var forbidden in unexpected)
                {
                    if (!output.Contains(forbidden, StringComparison.Ordinal))
                        continue;
                    Console.Error.WriteLine($"スモークテスト: 出力に不要な文字列がある: {forbidden}");
                    return 2;
                }
            }

            return 0;
        }
        catch (Exception ex)
        {
            Console.Error.WriteLine($"実行エラー: {ex.Message}");
            if (args.Contains("--trace-error", StringComparer.OrdinalIgnoreCase))
                Console.Error.WriteLine(ex);
            return 1;
        }
    }

    private static string[] SplitLines(string value) =>
        value.Split(['\r', '\n'], StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);

    private static string ResolveLanguageDirectory(string[] args)
    {
        var explicitDirectory = OptionValue(args, "--language-dir");
        if (!string.IsNullOrWhiteSpace(explicitDirectory))
            return Path.GetFullPath(explicitDirectory, Environment.CurrentDirectory);

        var language = OptionValue(args, "--language")
            ?? OptionValue(args, "--lang")
            ?? "ja";
        return Path.GetFullPath(Path.Combine(AppContext.BaseDirectory, "lang", language));
    }

    private static string? OptionValue(string[] args, string option)
    {
        for (var index = 0; index < args.Length; index++)
        {
            if (!args[index].Equals(option, StringComparison.OrdinalIgnoreCase))
                continue;
            if (index + 1 >= args.Length || args[index + 1].StartsWith("--", StringComparison.Ordinal))
                throw new ArgumentException($"{option} の値がない。");
            return args[index + 1];
        }
        return null;
    }

    private static byte[] ReadResource(Assembly assembly, string name)
    {
        using var stream = assembly.GetManifestResourceStream(name)
            ?? throw new InvalidOperationException($"埋め込みリソースが見つからない: {name}");
        using var memory = new MemoryStream();
        stream.CopyTo(memory);
        return memory.ToArray();
    }
}

internal interface IZMachineHost
{
    void Write(string text);
    string? ReadLine();
}

internal sealed class ConsoleHost : IZMachineHost
{
    private const string ProhibitedAtLineStart =
        "、。，．・：；？！ー―‐／\\～〜…‥ゝゞ々〃）〕］｝〉》」』】〙〗〟’”｠»" +
        "ぁぃぅぇぉっゃゅょゎァィゥェォッャュョヮヵヶ";
    private const string ProhibitedAtLineEnd =
        "（〔［｛〈《「『【〘〖〝‘“｟«";

    private int _column;

    public void Write(string text)
    {
        for (var index = 0; index < text.Length;)
        {
            if (text[index] == '\r')
            {
                index++;
                continue;
            }
            if (text[index] == '\n')
            {
                Console.WriteLine();
                _column = 0;
                index++;
                continue;
            }

            var tokenLength = KatakanaTokenLength(text, index);
            if (tokenLength > 0)
            {
                var token = text.Substring(index, tokenLength);
                var tokenWidth = DisplayWidth(token);
                if (_column > 0 && tokenWidth <= ContentWidth && _column + tokenWidth > ContentWidth)
                    NewLine();
                Console.Write(token);
                _column += tokenWidth;
                index += tokenLength;
                continue;
            }

            var rune = Rune.GetRuneAt(text, index);
            var character = rune.ToString();
            var width = DisplayWidth(rune);
            var contentWidth = ContentWidth;
            var lineStartProhibited = ProhibitedAtLineStart.Contains(character, StringComparison.Ordinal);
            var lineEndProhibited = ProhibitedAtLineEnd.Contains(character, StringComparison.Ordinal);

            if (_column > 0 &&
                (_column >= contentWidth && !lineStartProhibited ||
                 lineEndProhibited && _column + width >= contentWidth))
                NewLine();

            Console.Write(character);
            _column += width;
            index += rune.Utf16SequenceLength;
        }
    }

    public string? ReadLine()
    {
        var line = Console.ReadLine();
        _column = 0;
        return line;
    }

    private static int ContentWidth
    {
        get
        {
            try
            {
                // 禁則文字を行末へ追い込めるよう、端末の右端に少し余白を残す。
                return Math.Max(20, Console.WindowWidth - 4);
            }
            catch (IOException)
            {
                return 76;
            }
        }
    }

    private void NewLine()
    {
        Console.WriteLine();
        _column = 0;
    }

    private static int KatakanaTokenLength(string text, int start)
    {
        var index = start;
        var katakanaCount = 0;
        while (index < text.Length)
        {
            var rune = Rune.GetRuneAt(text, index);
            if (!IsKatakana(rune))
                break;
            katakanaCount++;
            index += rune.Utf16SequenceLength;
        }
        return katakanaCount >= 2 ? index - start : 0;
    }

    private static bool IsKatakana(Rune rune) =>
        rune.Value is >= 0x30a0 and <= 0x30ff or >= 0x31f0 and <= 0x31ff || rune.Value == 0x30fc;

    private static int DisplayWidth(string text)
    {
        var width = 0;
        foreach (var rune in text.EnumerateRunes())
            width += DisplayWidth(rune);
        return width;
    }

    private static int DisplayWidth(Rune rune) => rune.Value switch
    {
        < 0x20 => 0,
        <= 0x7e => 1,
        >= 0xff61 and <= 0xff9f => 1,
        _ => 2
    };
}

internal sealed class ScriptHost(IEnumerable<string> commands) : IZMachineHost
{
    private readonly Queue<string> _commands = new(commands);
    private readonly StringBuilder _output = new();

    public string Output => _output.ToString();
    public void Write(string text) => _output.Append(text);
    public string? ReadLine() => _commands.TryDequeue(out var command) ? command : "quit";
}
