using System.Text;
using System.Text.RegularExpressions;

namespace Zork1Japanese;

internal sealed partial class TranslationCatalog
{
    private readonly Dictionary<string, string> _output;
    private readonly Dictionary<string, string> _input;
    private readonly Dictionary<string, string> _nounOutput;
    private readonly List<(string Japanese, string English)> _verbs;
    private readonly Dictionary<string, string> _verbInput;
    private readonly HashSet<string> _englishVerbs;
    private readonly Dictionary<string, string> _ui;
    private readonly int _ambiguousOutputCount;

    private TranslationCatalog(
        Dictionary<string, string> output,
        Dictionary<string, string> input,
        Dictionary<string, string> nounOutput,
        List<(string Japanese, string English)> verbs,
        Dictionary<string, string> verbInput,
        HashSet<string> englishVerbs,
        Dictionary<string, string> ui,
        int ambiguousOutputCount)
    {
        _output = output;
        _input = input;
        _nounOutput = nounOutput;
        _verbs = verbs;
        _verbInput = verbInput;
        _englishVerbs = englishVerbs;
        _ui = ui;
        _ambiguousOutputCount = ambiguousOutputCount;
    }

    public static TranslationCatalog Load(string languageDirectory)
    {
        languageDirectory = Path.GetFullPath(languageDirectory);
        if (!Directory.Exists(languageDirectory))
            throw new DirectoryNotFoundException($"言語パックが見つからない: {languageDirectory}");

        var candidates = new Dictionary<string, List<(string Japanese, int Weight)>>(StringComparer.Ordinal);
        var input = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        var nounOutput = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        var explicitDictionaryOutput = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        var verbs = new List<(string Japanese, string English)>();
        var verbInput = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        var englishVerbs = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        var ui = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);

        foreach (var resource in new[] { "messages", "objects", "rooms" })
        {
            var table = ReadTable(languageDirectory, $"{resource}.tsv");
            foreach (var row in table)
            {
                if (!row.TryGetValue("english", out var english))
                    continue;
                var translated = row.GetValueOrDefault(
                    "translation",
                    row.GetValueOrDefault("japanese", ""));

                var status = row.GetValueOrDefault("status", "");
                if (string.IsNullOrEmpty(translated) && status != "format")
                    continue;
                english = NormalizeOutputKey(Unescape(english));
                translated = Unescape(translated);
                var weight = status == "machine-draft" ? 1 : 3;
                if (!candidates.TryGetValue(english, out var list))
                    candidates[english] = list = [];
                list.Add((translated, weight));

                if (resource == "objects" &&
                    row.GetValueOrDefault("property", "").Equals("DESC", StringComparison.OrdinalIgnoreCase))
                {
                    var noun = LastEnglishWord(english);
                    AddInput(input, translated, noun);
                    foreach (var alias in SingularJapaneseAliases(translated))
                        AddInput(input, alias, noun);
                    AddDictionaryOutput(nounOutput, noun, translated == english ? noun : translated);
                }
            }
        }

        foreach (var row in ReadTable(languageDirectory, "verbs.tsv"))
        {
            var disposition = row.GetValueOrDefault("disposition", "keep");
            if (disposition == "omit")
                continue;
            var english = row.GetValueOrDefault("verb", "").TrimStart('\\').ToLowerInvariant();
            if (english.Length == 0)
                continue;
            englishVerbs.Add(english);
            var japanese = row.GetValueOrDefault("input", row.GetValueOrDefault("japanese", ""));
            AddVerb(japanese, english);
            AddDictionaryOutput(nounOutput, english, japanese);
            foreach (var alias in SplitAliases(row.GetValueOrDefault("aliases", "")))
                AddVerb(alias, english);
        }

        foreach (var row in ReadTable(languageDirectory, "directions.tsv"))
        {
            var english = row.GetValueOrDefault("english", "").ToLowerInvariant();
            var japanese = row.GetValueOrDefault("input", row.GetValueOrDefault("japanese", ""));
            AddInput(input, japanese, english);
            AddDictionaryOutput(nounOutput, english, japanese);
            foreach (var alias in SplitAliases(row.GetValueOrDefault("aliases", "")))
                input[NormalizeJapanese(alias)] = english;
        }

        foreach (var row in ReadTable(languageDirectory, "input.tsv"))
        {
            var phrase = row.GetValueOrDefault("input", "");
            var english = row.GetValueOrDefault("english", "");
            if (phrase.Length != 0 && english.Length != 0)
            {
                input[NormalizeJapanese(phrase)] = english.Trim().ToLowerInvariant();
                english = english.Trim().ToLowerInvariant();
                if (!english.Contains(' ') && explicitDictionaryOutput.Add(english))
                    AddDictionaryOutput(nounOutput, english, phrase, overwrite: true);
            }
        }

        foreach (var row in ReadTable(languageDirectory, "ui.tsv"))
        {
            var key = row.GetValueOrDefault("key", "").Trim();
            if (key.Length != 0)
                ui[key] = Unescape(row.GetValueOrDefault("value", ""));
        }

        var output = new Dictionary<string, string>(StringComparer.Ordinal);
        var ambiguous = 0;
        foreach (var (english, values) in candidates)
        {
            var grouped = values
                .GroupBy(value => value.Japanese, StringComparer.Ordinal)
                .Select(group => (Japanese: group.Key, Weight: group.Sum(value => value.Weight)))
                .OrderByDescending(value => value.Weight)
                .ThenByDescending(value => value.Japanese.Length)
                .ToArray();
            output[english] = grouped[0].Japanese;
            if (grouped.Length > 1)
                ambiguous++;
        }

        verbs.Sort((left, right) => right.Japanese.Length.CompareTo(left.Japanese.Length));
        return new TranslationCatalog(output, input, nounOutput, verbs, verbInput, englishVerbs, ui, ambiguous);

        void AddVerb(string japanese, string english)
        {
            japanese = NormalizeJapanese(japanese);
            if (japanese.Length == 0)
                return;
            AddInput(input, japanese, english);
            verbInput.TryAdd(japanese, english);
            verbs.Add((japanese, english));
        }
    }

    public string TranslateOutput(string english)
    {
        if (english.Length == 1)
            return TranslateCharacter(english);
        var key = NormalizeOutputKey(english);
        if (_output.TryGetValue(key, out var translated))
            return translated;
        return _nounOutput.GetValueOrDefault(key, english);
    }

    public string TranslateInput(string line)
    {
        line = NormalizeJapanese(line).ToLowerInvariant();
        if (line.Length == 0 || AsciiOnlyRegex().IsMatch(line))
            return line;
        if (_input.TryGetValue(line, out var exact))
            return exact;

        var spaced = WhitespaceRegex().Split(line).Where(token => token.Length != 0).ToList();
        if (spaced.Count > 1)
        {
            var translated = spaced
                .Where(token => !IsParticle(token))
                .Select(token =>
                {
                    var word = TrimParticle(token);
                    return _verbInput.GetValueOrDefault(word, _input.GetValueOrDefault(word, token));
                })
                .ToList();
            var verbIndex = translated.FindIndex(token => _englishVerbs.Contains(token));
            if (verbIndex > 0)
            {
                var verb = translated[verbIndex];
                translated.RemoveAt(verbIndex);
                translated.Insert(0, verb);
            }
            if (translated.Count > 1 && translated[0] == "look")
                translated[0] = "examine";
            return string.Join(' ', translated);
        }

        foreach (var (japanese, english) in _verbs)
        {
            if (line.Length > japanese.Length && line.EndsWith(japanese, StringComparison.Ordinal))
            {
                var noun = TrimParticle(line[..^japanese.Length]);
                var command = english == "look" ? "examine" : english;
                return $"{command} {TranslateNoun(noun)}".TrimEnd();
            }
            if (line.Length > japanese.Length && line.StartsWith(japanese, StringComparison.Ordinal))
            {
                var noun = TrimParticle(line[japanese.Length..]);
                var command = english == "look" ? "examine" : english;
                return $"{command} {TranslateNoun(noun)}".TrimEnd();
            }
        }

        return line;
    }

    public string Report() =>
        string.Format(
            Ui("catalog.report", "表示訳: {0}件\n入力語: {1}件\n同一原文に複数訳がある項目: {2}件"),
            _output.Count,
            _input.Count,
            _ambiguousOutputCount);

    public string Ui(string key, string fallback) => _ui.GetValueOrDefault(key, fallback);

    public string FormatUi(string key, string fallback, params object[] values) =>
        string.Format(Ui(key, fallback), values);

    public string TranslateCharacter(string character)
    {
        if (character.Length != 1)
            return character;
        return Ui($"character.{(int)character[0]}", character);
    }

    private string TranslateNoun(string noun) => _input.GetValueOrDefault(noun, noun);

    private static string TrimParticle(string value)
    {
        value = value.Trim();
        foreach (var particle in new[] { "から", "まで", "へ", "を", "に", "で", "と", "が", "は", "の" })
        {
            if (value.EndsWith(particle, StringComparison.Ordinal))
                return value[..^particle.Length];
            if (value.StartsWith(particle, StringComparison.Ordinal))
                return value[particle.Length..];
        }
        return value;
    }

    private static bool IsParticle(string value) =>
        value is "から" or "まで" or "へ" or "を" or "に" or "で" or "と" or "が" or "は" or "の";

    private static string NormalizeJapanese(string value) =>
        value.Replace('　', ' ').Trim();

    private static void AddInput(Dictionary<string, string> input, string japanese, string english)
    {
        japanese = NormalizeJapanese(japanese);
        english = english.Trim().ToLowerInvariant();
        if (japanese.Length != 0 && english.Length != 0)
            input.TryAdd(japanese, english);
    }

    private static void AddDictionaryOutput(
        Dictionary<string, string> output,
        string english,
        string japanese,
        bool overwrite = false)
    {
        english = english.Trim().ToLowerInvariant();
        japanese = NormalizeJapanese(japanese);
        if (english.Length == 0 || japanese.Length == 0)
            return;
        foreach (var key in new[] { english, english[..Math.Min(6, english.Length)] }.Distinct())
        {
            if (overwrite)
                output[key] = japanese;
            else
                output.TryAdd(key, japanese);
        }
    }

    private static IEnumerable<string> SplitAliases(string aliases) =>
        WhitespaceRegex().Split(aliases.Replace('、', ' ')).Where(alias => alias.Length != 0);

    private static IEnumerable<string> SingularJapaneseAliases(string japanese)
    {
        foreach (var suffix in new[] { "たち", "達", "ども" })
        {
            if (japanese.EndsWith(suffix, StringComparison.Ordinal) && japanese.Length > suffix.Length)
                yield return japanese[..^suffix.Length];
        }
    }

    private static string LastEnglishWord(string english)
    {
        var matches = EnglishWordRegex().Matches(english);
        return matches.Count == 0 ? english.ToLowerInvariant() : matches[^1].Value.ToLowerInvariant();
    }

    private static string Unescape(string value) =>
        value.Replace("|\\n", "\n", StringComparison.Ordinal)
             .Replace("|", "\n", StringComparison.Ordinal)
             .Replace("\\n", "\n", StringComparison.Ordinal)
             .Replace("\\t", "\t", StringComparison.Ordinal);

    private static string NormalizeOutputKey(string value) =>
        OutputWhitespaceRegex().Replace(value, " ");

    private static List<Dictionary<string, string>> ReadTable(string languageDirectory, string fileName)
    {
        var path = Path.Combine(languageDirectory, fileName);
        if (!File.Exists(path))
            throw new FileNotFoundException($"言語パックの必須ファイルが見つからない: {path}", path);
        using var reader = new StreamReader(path, new UTF8Encoding(false), true);
        var headerLine = reader.ReadLine() ?? throw new InvalidDataException($"空のTSV: {path}");
        var headers = ParseLine(headerLine);
        var rows = new List<Dictionary<string, string>>();
        while (reader.ReadLine() is { } line)
        {
            var fields = ParseLine(line);
            if (fields.Count != headers.Count)
                throw new InvalidDataException($"TSV列数が不正: {path} ({rows.Count + 2}行目)");
            var row = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
            for (var index = 0; index < headers.Count; index++)
                row[headers[index]] = fields[index];
            rows.Add(row);
        }
        return rows;
    }

    private static List<string> ParseLine(string line)
    {
        var fields = new List<string>();
        var field = new StringBuilder();
        var quoted = false;
        for (var index = 0; index < line.Length; index++)
        {
            var character = line[index];
            if (character == '"')
            {
                if (quoted && index + 1 < line.Length && line[index + 1] == '"')
                {
                    field.Append('"');
                    index++;
                }
                else
                {
                    quoted = !quoted;
                }
            }
            else if (character == '\t' && !quoted)
            {
                fields.Add(field.ToString());
                field.Clear();
            }
            else
            {
                field.Append(character);
            }
        }
        fields.Add(field.ToString());
        return fields;
    }

    [GeneratedRegex("^[\\x00-\\x7f]*$")]
    private static partial Regex AsciiOnlyRegex();

    [GeneratedRegex("\\s+")]
    private static partial Regex WhitespaceRegex();

    [GeneratedRegex("[A-Za-z#]+")]
    private static partial Regex EnglishWordRegex();

    [GeneratedRegex("[ \\t\\r\\n]+")]
    private static partial Regex OutputWhitespaceRegex();
}
