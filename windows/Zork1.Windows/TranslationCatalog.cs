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
    private readonly Dictionary<string, string> _placementPrepositions;
    private readonly HashSet<string> _englishVerbs;
    private readonly Dictionary<string, string> _ui;
    private readonly int _ambiguousOutputCount;
    private List<(string English, string Japanese)>? _pendingSyntaxPrompt;
    private bool _suppressNextFullStop;

    private TranslationCatalog(
        Dictionary<string, string> output,
        Dictionary<string, string> input,
        Dictionary<string, string> nounOutput,
        List<(string Japanese, string English)> verbs,
        Dictionary<string, string> verbInput,
        Dictionary<string, string> placementPrepositions,
        HashSet<string> englishVerbs,
        Dictionary<string, string> ui,
        int ambiguousOutputCount)
    {
        _output = output;
        _input = input;
        _nounOutput = nounOutput;
        _verbs = verbs;
        _verbInput = verbInput;
        _placementPrepositions = placementPrepositions;
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
        var placementPrepositions = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
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
                foreach (var preposition in new[] { "in", "on" })
                {
                    if (english.StartsWith($"{preposition} ", StringComparison.Ordinal))
                        placementPrepositions.TryAdd(english[(preposition.Length + 1)..], preposition);
                }
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
        return new TranslationCatalog(
            output,
            input,
            nounOutput,
            verbs,
            verbInput,
            placementPrepositions,
            englishVerbs,
            ui,
            ambiguous);

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
        {
            if (english[0] == '.' && _suppressNextFullStop)
            {
                _suppressNextFullStop = false;
                return "";
            }
            return TranslateCharacter(english);
        }
        var key = NormalizeOutputKey(english);
        if (key.Equals("What do you want to ", StringComparison.Ordinal))
        {
            _pendingSyntaxPrompt = [];
            return "";
        }

        var translated = _output.GetValueOrDefault(key, _nounOutput.GetValueOrDefault(key, english));
        if (key.Equals(" reveals ", StringComparison.Ordinal))
            _suppressNextFullStop = translated.EndsWith('：');
        if (_pendingSyntaxPrompt is not null)
        {
            _pendingSyntaxPrompt.Add((key, translated));
            return "";
        }
        return translated;
    }

    public string TranslateInput(string line)
    {
        line = NormalizeJapanese(line).ToLowerInvariant();
        if (line.Length == 0)
            return line;
        if (AsciiOnlyRegex().IsMatch(line))
            return line;
        if (_input.TryGetValue(line, out var exact))
            return exact;

        var spaced = WhitespaceRegex().Split(line).Where(token => token.Length != 0).ToList();
        if (spaced.Count > 1)
        {
            var compact = string.Concat(spaced);
            foreach (var (japanese, english) in _verbs)
            {
                if (compact.Length <= japanese.Length ||
                    !compact.EndsWith(japanese, StringComparison.Ordinal))
                    continue;
                if (english is "drop" or "put" &&
                    TryTranslatePlacement(compact[..^japanese.Length], out var placement))
                    return placement;
                if (english == "apply" &&
                    TryTranslateApply(compact[..^japanese.Length], out var application))
                    return application;
            }
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
            if (translated.Count == 3 && translated[0] is "drop" or "put")
            {
                if (translated[2].StartsWith("in ", StringComparison.Ordinal) ||
                    translated[2].StartsWith("on ", StringComparison.Ordinal))
                {
                    translated[0] = "put";
                }
                else if (_placementPrepositions.TryGetValue(translated[2], out var preposition))
                {
                    translated[0] = "put";
                    translated.Insert(2, preposition);
                }
            }
            if (translated.Count == 3 && translated[0] == "apply")
            {
                if (IsSelfObject(translated[2]))
                {
                    var weapon = translated[1];
                    translated.Clear();
                    translated.AddRange(["attack", "me", "with", weapon]);
                }
                else
                {
                    translated.Insert(2, "to");
                }
            }
            if (translated.Count > 1 && translated[0] == "look")
                translated[0] = "examine";
            return string.Join(' ', translated);
        }

        foreach (var (japanese, english) in _verbs)
        {
            if (line.Length > japanese.Length && line.EndsWith(japanese, StringComparison.Ordinal))
            {
                if (english is "drop" or "put" &&
                    TryTranslatePlacement(line[..^japanese.Length], out var placement))
                    return placement;
                if (english == "apply" &&
                    TryTranslateApply(line[..^japanese.Length], out var application))
                    return application;
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

    private bool TryTranslateApply(string arguments, out string command)
    {
        arguments = arguments.Trim();
        if (arguments.EndsWith("を", StringComparison.Ordinal))
        {
            var targetMarker = arguments.IndexOf('に');
            if (targetMarker > 0 && targetMarker < arguments.Length - 2)
                return BuildApplication(
                    arguments[(targetMarker + 1)..^1],
                    arguments[..targetMarker],
                    out command);
        }
        if (arguments.EndsWith("に", StringComparison.Ordinal))
        {
            var directMarker = arguments.IndexOf('を');
            if (directMarker > 0 && directMarker < arguments.Length - 2)
                return BuildApplication(
                    arguments[..directMarker],
                    arguments[(directMarker + 1)..^1],
                    out command);
        }
        command = "";
        return false;
    }

    private bool BuildApplication(string directJapanese, string targetJapanese, out string command)
    {
        var direct = TranslateNoun(directJapanese);
        var target = TranslateNoun(targetJapanese);
        if (direct == directJapanese || target == targetJapanese)
        {
            command = "";
            return false;
        }
        command = IsSelfObject(target)
            ? $"attack me with {direct}"
            : $"apply {direct} to {target}";
        return true;
    }

    private bool TryTranslatePlacement(string arguments, out string command)
    {
        foreach (var (marker, explicitPreposition) in new[]
                 {
                     ("の中に", "in"), ("の中へ", "in"),
                     ("の上に", "on"), ("の上へ", "on"),
                     ("に", ""), ("へ", "")
                 })
        {
            var markerIndex = arguments.IndexOf(marker, StringComparison.Ordinal);
            if (markerIndex > 0 && arguments.EndsWith("を", StringComparison.Ordinal))
            {
                var indirect = arguments[..markerIndex];
                var direct = arguments[(markerIndex + marker.Length)..^1];
                if (BuildPlacement(direct, indirect, explicitPreposition, out command))
                    return true;
            }

            if (!arguments.EndsWith(marker, StringComparison.Ordinal))
                continue;
            var core = arguments[..^marker.Length];
            var particleIndex = core.IndexOf('を');
            if (particleIndex > 0 && particleIndex < core.Length - 1 &&
                BuildPlacement(
                    core[..particleIndex],
                    core[(particleIndex + 1)..],
                    explicitPreposition,
                    out command))
                return true;
        }
        command = "";
        return false;
    }

    private bool BuildPlacement(
        string directJapanese,
        string indirectJapanese,
        string explicitPreposition,
        out string command)
    {
        var direct = TranslateNoun(directJapanese);
        var indirect = TranslateNoun(indirectJapanese);
        var preposition = explicitPreposition;
        if (preposition.Length == 0 && !_placementPrepositions.TryGetValue(indirect, out preposition))
        {
            command = "";
            return false;
        }
        command = $"put {direct} {preposition} {indirect}";
        return true;
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
        if (character == "?" && _pendingSyntaxPrompt is not null)
        {
            var prompt = FormatSyntaxPrompt(_pendingSyntaxPrompt);
            _pendingSyntaxPrompt = null;
            return prompt + Ui("character.63", "？");
        }
        return Ui($"character.{(int)character[0]}", character);
    }

    private static string FormatSyntaxPrompt(IReadOnlyList<(string English, string Japanese)> parts)
    {
        if (parts.Count == 0)
            return "何をするのだ";

        var verb = parts[0].Japanese;
        if (parts.Count >= 3 && TryPromptParticle(parts[^1].English, out var particle))
        {
            var direct = string.Concat(parts.Skip(1).Take(parts.Count - 2).Select(part => part.Japanese));
            return $"{direct}を何{particle}{verb}";
        }
        return $"何を{verb}";
    }

    private static bool TryPromptParticle(string english, out string particle)
    {
        particle = english.Trim().ToLowerInvariant() switch
        {
            "with" => "で",
            "from" => "から",
            "in" or "inside" => "の中に",
            "on" => "の上に",
            "under" => "の下に",
            "through" => "を通して",
            "to" or "at" => "に",
            _ => ""
        };
        return particle.Length != 0;
    }

    private static bool IsSelfObject(string english) =>
        english is "me" or "myself" or "self" or "cretin" or "you";

    private string TranslateNoun(string noun) => _input.GetValueOrDefault(noun, noun);

    private static string TrimParticle(string value)
    {
        value = value.Trim();
        foreach (var particle in new[] { "から", "まで", "へ", "を", "に", "で", "と", "が", "は", "の" })
        {
            if (value.EndsWith(particle, StringComparison.Ordinal))
                return value[..^particle.Length];
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
