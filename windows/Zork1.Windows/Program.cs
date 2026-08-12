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
            var story = ReadResource(assembly, "Zork1Japanese.zork1.z3");
            var english = args.Contains("--english", StringComparer.OrdinalIgnoreCase);
            var catalogReport = args.Contains("--catalog-report", StringComparer.OrdinalIgnoreCase);
            var languageDirectory = ResolveLanguageDirectory(args);
            var catalog = !english || catalogReport
                ? TranslationCatalog.Load(languageDirectory)
                : null;

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
    public void Write(string text) => Console.Write(text);
    public string? ReadLine() => Console.ReadLine();
}

internal sealed class ScriptHost(IEnumerable<string> commands) : IZMachineHost
{
    private readonly Queue<string> _commands = new(commands);
    private readonly StringBuilder _output = new();

    public string Output => _output.ToString();
    public void Write(string text) => _output.Append(text);
    public string? ReadLine() => _commands.TryDequeue(out var command) ? command : "quit";
}
