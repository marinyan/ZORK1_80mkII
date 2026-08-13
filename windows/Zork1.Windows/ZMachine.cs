using System.Text;

namespace Zork1Japanese;

internal sealed class ZMachine
{
    private readonly byte[] _original;
    private readonly IZMachineHost _host;
    private readonly TranslationCatalog? _translation;
    private readonly Random _random = new();
    private readonly Stack<Frame> _frames = new();
    private readonly Queue<char> _inputEchoCharacters = new();
    private readonly StringBuilder _printCharacterBuffer = new();
    private readonly List<ScreenSegment> _screenLine = [];
    private byte[] _memory;
    private Random _seededRandom = new();
    private int _pc;
    private bool _running;
    private bool _screenEnabled = true;
    private int? _memoryStream;

    private int DictionaryAddress => ReadWord(0x08);
    private int ObjectTableAddress => ReadWord(0x0a);
    private int GlobalsAddress => ReadWord(0x0c);
    private int AbbreviationsAddress => ReadWord(0x18);
    private Frame Current => _frames.Peek();

    public ZMachine(byte[] story, IZMachineHost host, TranslationCatalog? translation)
    {
        if (story.Length < 64 || story[0] != 3)
            throw new InvalidDataException("この検証版が実行できるのはVersion 3のZ-codeだけだ。");
        _original = (byte[])story.Clone();
        _memory = (byte[])story.Clone();
        _host = host;
        _translation = translation;
        Reset();
    }

    public void Run(int instructionLimit)
    {
        _running = true;
        for (var count = 0; _running && count < instructionLimit; count++)
            Step();
        FlushPrintCharacterBuffer();
        FlushScreenLine();
        if (_running && instructionLimit != int.MaxValue)
            throw new InvalidOperationException($"命令数上限({instructionLimit:N0})に達した。PC=${_pc:x4}");
    }

    private void Reset()
    {
        Array.Copy(_original, _memory, _original.Length);
        _pc = ReadWord(0x06);
        _frames.Clear();
        _frames.Push(new Frame(-1, -1, []));
        _screenEnabled = true;
        _memoryStream = null;
        _printCharacterBuffer.Clear();
        _screenLine.Clear();
    }

    private void Step()
    {
        var instructionAddress = _pc;
        var opcodeByte = ReadByte(_pc++);
        var operands = new List<ushort>(4);
        int opcode;
        OpcodeClass opcodeClass;

        if ((opcodeByte & 0xc0) == 0x80)
        {
            opcode = opcodeByte & 0x0f;
            var type = (opcodeByte >> 4) & 0x03;
            if (type == 3)
            {
                opcodeClass = OpcodeClass.Zero;
            }
            else
            {
                opcodeClass = OpcodeClass.One;
                operands.Add(ReadOperand(type));
            }
        }
        else if ((opcodeByte & 0xc0) == 0xc0)
        {
            opcode = opcodeByte & 0x1f;
            opcodeClass = (opcodeByte & 0x20) == 0 ? OpcodeClass.Two : OpcodeClass.Variable;
            ReadVariableOperands(operands);
        }
        else
        {
            opcode = opcodeByte & 0x1f;
            opcodeClass = OpcodeClass.Two;
            operands.Add(ReadOperand((opcodeByte & 0x40) == 0 ? 1 : 2));
            operands.Add(ReadOperand((opcodeByte & 0x20) == 0 ? 1 : 2));
        }

        try
        {
            switch (opcodeClass)
            {
                case OpcodeClass.Zero:
                    ExecuteZero(opcode);
                    break;
                case OpcodeClass.One:
                    ExecuteOne(opcode, operands[0]);
                    break;
                case OpcodeClass.Two:
                    ExecuteTwo(opcode, operands);
                    break;
                case OpcodeClass.Variable:
                    ExecuteVariable(opcode, operands);
                    break;
            }
        }
        catch (Exception exception) when (exception is not ZMachineException)
        {
            throw new ZMachineException(
                $"Z-machine命令の実行に失敗した: PC=${instructionAddress:x4}, opcode={opcodeClass}:{opcode:x2}",
                exception);
        }
    }

    private void ReadVariableOperands(List<ushort> operands)
    {
        var types = ReadByte(_pc++);
        for (var shift = 6; shift >= 0; shift -= 2)
        {
            var type = (types >> shift) & 3;
            if (type == 3)
                break;
            operands.Add(ReadOperand(type));
        }
    }

    private ushort ReadOperand(int type) => type switch
    {
        0 => ReadNextWord(),
        1 => ReadByte(_pc++),
        2 => ReadVariable(ReadByte(_pc++)),
        _ => throw new InvalidOperationException("省略オペランドを読み込もうとした。")
    };

    private void ExecuteTwo(int opcode, IReadOnlyList<ushort> op)
    {
        switch (opcode)
        {
            case 1: Branch(op.Count >= 2 && op.Skip(1).Any(value => value == op[0])); break;
            case 2: Branch(Signed(op[0]) < Signed(op[1])); break;
            case 3: Branch(Signed(op[0]) > Signed(op[1])); break;
            case 4:
            {
                var value = unchecked((ushort)(ReadVariableIndirect(op[0]) - 1));
                WriteVariableIndirect(op[0], value);
                Branch(Signed(value) < Signed(op[1]));
                break;
            }
            case 5:
            {
                var value = unchecked((ushort)(ReadVariableIndirect(op[0]) + 1));
                WriteVariableIndirect(op[0], value);
                Branch(Signed(value) > Signed(op[1]));
                break;
            }
            case 6: Branch(GetParent(op[0]) == op[1]); break;
            case 7: Branch((op[0] & op[1]) == op[1]); break;
            case 8: StoreResult((ushort)(op[0] | op[1])); break;
            case 9: StoreResult((ushort)(op[0] & op[1])); break;
            case 10: Branch(TestAttribute(op[0], op[1])); break;
            case 11: SetAttribute(op[0], op[1], true); break;
            case 12: SetAttribute(op[0], op[1], false); break;
            case 13: WriteVariableIndirect(op[0], op[1]); break;
            case 14: InsertObject(op[0], op[1]); break;
            case 15: StoreResult(ReadWord(op[0] + 2 * op[1])); break;
            case 16: StoreResult(ReadByte(op[0] + op[1])); break;
            case 17: StoreResult(GetProperty(op[0], op[1])); break;
            case 18: StoreResult((ushort)GetPropertyAddress(op[0], op[1])); break;
            case 19: StoreResult(GetNextProperty(op[0], op[1])); break;
            case 20: StoreResult(unchecked((ushort)(op[0] + op[1]))); break;
            case 21: StoreResult(unchecked((ushort)(op[0] - op[1]))); break;
            case 22: StoreResult(unchecked((ushort)(Signed(op[0]) * Signed(op[1])))); break;
            case 23:
                if (op[1] == 0) throw new DivideByZeroException();
                StoreResult(unchecked((ushort)(Signed(op[0]) / Signed(op[1]))));
                break;
            case 24:
                if (op[1] == 0) throw new DivideByZeroException();
                StoreResult(unchecked((ushort)(Signed(op[0]) % Signed(op[1]))));
                break;
            default: throw Unsupported(OpcodeClass.Two, opcode);
        }
    }

    private void ExecuteOne(int opcode, ushort operand)
    {
        switch (opcode)
        {
            case 0: Branch(operand == 0); break;
            case 1:
            {
                var sibling = GetSibling(operand);
                StoreResult(sibling);
                Branch(sibling != 0);
                break;
            }
            case 2:
            {
                var child = GetChild(operand);
                StoreResult(child);
                Branch(child != 0);
                break;
            }
            case 3: StoreResult(GetParent(operand)); break;
            case 4: StoreResult(GetPropertyLength(operand)); break;
            case 5: WriteVariableIndirect(operand, unchecked((ushort)(ReadVariableIndirect(operand) + 1))); break;
            case 6: WriteVariableIndirect(operand, unchecked((ushort)(ReadVariableIndirect(operand) - 1))); break;
            case 7: PrintZString(operand); break;
            case 8: throw Unsupported(OpcodeClass.One, opcode);
            case 9: RemoveObject(operand); break;
            case 10: PrintObject(operand); break;
            case 11: Return(operand); break;
            case 12: _pc += Signed(operand) - 2; break;
            case 13: PrintZString(operand * 2); break;
            case 14: StoreResult(ReadVariableIndirect(operand)); break;
            case 15: StoreResult((ushort)~operand); break;
            default: throw Unsupported(OpcodeClass.One, opcode);
        }
    }

    private void ExecuteZero(int opcode)
    {
        switch (opcode)
        {
            case 0: Return(1); break;
            case 1: Return(0); break;
            case 2:
            {
                var text = DecodeZString(_pc, out var next);
                _pc = next;
                WriteText(text, true);
                break;
            }
            case 3:
            {
                var text = DecodeZString(_pc, out var next);
                _pc = next;
                WriteText(text, true);
                WriteText("\n", false);
                Return(1);
                break;
            }
            case 4: break;
            case 5: Branch(false); break;
            case 6: Branch(false); break;
            case 7: Reset(); break;
            case 8: Return(Pop()); break;
            case 9: _ = Pop(); break;
            case 10: _running = false; break;
            case 11: WriteText("\n", false); break;
            case 12: ShowStatus(); break;
            case 13: Branch(VerifyChecksum()); break;
            default: throw Unsupported(OpcodeClass.Zero, opcode);
        }
    }

    private void ExecuteVariable(int opcode, IReadOnlyList<ushort> op)
    {
        switch (opcode)
        {
            case 0: Call(op); break;
            case 1: WriteWord(op[0] + 2 * op[1], op[2]); break;
            case 2: WriteByte(op[0] + op[1], (byte)op[2]); break;
            case 3: PutProperty(op[0], op[1], op[2]); break;
            case 4: ReadCommand(op[0], op[1]); break;
            case 5:
            {
                var character = ZsciiToString(op[0]);
                if (character == "?" && _inputEchoCharacters.TryDequeue(out var originalCharacter))
                    WriteText(originalCharacter.ToString(), false);
                else
                    WriteCharacter(character);
                break;
            }
            case 6: WriteText(Signed(op[0]).ToString(), false); break;
            case 7: Random(op[0]); break;
            case 8: Push(op[0]); break;
            case 9: WriteVariableIndirect(op[0], Pop()); break;
            case 10: break;
            case 11: break;
            case 19: SelectOutputStream(op); break;
            case 20: break;
            case 21: break;
            default: throw Unsupported(OpcodeClass.Variable, opcode);
        }
    }

    private void Call(IReadOnlyList<ushort> operands)
    {
        var storeVariable = ReadByte(_pc++);
        var packedAddress = operands[0];
        if (packedAddress == 0)
        {
            WriteVariable(storeVariable, 0);
            return;
        }

        var address = packedAddress * 2;
        var localCount = ReadByte(address++);
        if (localCount > 15)
            throw new InvalidDataException($"不正なローカル変数数: {localCount}");
        var locals = new ushort[localCount];
        for (var index = 0; index < localCount; index++)
        {
            locals[index] = ReadWord(address);
            address += 2;
        }
        for (var index = 1; index < operands.Count && index <= localCount; index++)
            locals[index - 1] = operands[index];

        _frames.Push(new Frame(_pc, storeVariable, locals));
        _pc = address;
    }

    private void Return(ushort value)
    {
        if (_frames.Count <= 1)
        {
            _running = false;
            return;
        }
        var completed = _frames.Pop();
        _pc = completed.ReturnAddress;
        WriteVariable(completed.StoreVariable, value);
    }

    private void Branch(bool condition)
    {
        var first = ReadByte(_pc++);
        var branchOnTrue = (first & 0x80) != 0;
        int offset;
        if ((first & 0x40) != 0)
        {
            offset = first & 0x3f;
        }
        else
        {
            offset = ((first & 0x3f) << 8) | ReadByte(_pc++);
            if ((offset & 0x2000) != 0)
                offset -= 0x4000;
        }

        if (condition != branchOnTrue)
            return;
        if (offset == 0)
            Return(0);
        else if (offset == 1)
            Return(1);
        else
            _pc += offset - 2;
    }

    private void StoreResult(ushort value) => WriteVariable(ReadByte(_pc++), value);

    private ushort ReadVariable(int variable)
    {
        if (variable == 0)
            return Pop();
        if (variable < 16)
        {
            if (variable > Current.Locals.Length)
                throw new InvalidDataException($"存在しないローカル変数を読み込んだ: {variable}");
            return Current.Locals[variable - 1];
        }
        return ReadWord(GlobalsAddress + 2 * (variable - 16));
    }

    private void WriteVariable(int variable, ushort value)
    {
        if (variable == 0)
        {
            Push(value);
            return;
        }
        if (variable < 16)
        {
            if (variable > Current.Locals.Length)
                throw new InvalidDataException($"存在しないローカル変数へ書き込んだ: {variable}");
            Current.Locals[variable - 1] = value;
            return;
        }
        WriteWord(GlobalsAddress + 2 * (variable - 16), value);
    }

    private ushort ReadVariableIndirect(ushort variable)
    {
        if (variable == 0)
            return Peek();
        return ReadVariable(variable);
    }

    private void WriteVariableIndirect(ushort variable, ushort value)
    {
        if (variable == 0)
        {
            if (Current.Stack.Count == 0)
                throw new InvalidOperationException("空のスタック先頭へ書き込もうとした。");
            Current.Stack[^1] = value;
        }
        else
        {
            WriteVariable(variable, value);
        }
    }

    private void Push(ushort value) => Current.Stack.Add(value);

    private ushort Pop()
    {
        if (Current.Stack.Count == 0)
            throw new InvalidOperationException("空のスタックから値を取り出そうとした。");
        var index = Current.Stack.Count - 1;
        var value = Current.Stack[index];
        Current.Stack.RemoveAt(index);
        return value;
    }

    private ushort Peek()
    {
        if (Current.Stack.Count == 0)
            throw new InvalidOperationException("空のスタックを参照しようとした。");
        return Current.Stack[^1];
    }

    private int ObjectAddress(ushort number)
    {
        if (number == 0)
            return 0;
        return ObjectTableAddress + 62 + (number - 1) * 9;
    }

    private ushort GetParent(ushort number) => number == 0 ? (ushort)0 : ReadByte(ObjectAddress(number) + 4);
    private ushort GetSibling(ushort number) => number == 0 ? (ushort)0 : ReadByte(ObjectAddress(number) + 5);
    private ushort GetChild(ushort number) => number == 0 ? (ushort)0 : ReadByte(ObjectAddress(number) + 6);

    private bool TestAttribute(ushort number, ushort attribute)
    {
        if (number == 0 || attribute >= 32)
            return false;
        var address = ObjectAddress(number) + attribute / 8;
        var mask = 0x80 >> (attribute % 8);
        return (ReadByte(address) & mask) != 0;
    }

    private void SetAttribute(ushort number, ushort attribute, bool set)
    {
        if (number == 0 || attribute >= 32)
            throw new InvalidDataException("不正な物体属性番号だ。");
        var address = ObjectAddress(number) + attribute / 8;
        var mask = 0x80 >> (attribute % 8);
        var value = ReadByte(address);
        WriteByte(address, (byte)(set ? value | mask : value & ~mask));
    }

    private void RemoveObject(ushort number)
    {
        if (number == 0)
            return;
        var parent = GetParent(number);
        var sibling = GetSibling(number);
        if (parent != 0)
        {
            var parentAddress = ObjectAddress(parent);
            var child = GetChild(parent);
            if (child == number)
            {
                WriteByte(parentAddress + 6, (byte)sibling);
            }
            else
            {
                while (child != 0 && GetSibling(child) != number)
                    child = GetSibling(child);
                if (child != 0)
                    WriteByte(ObjectAddress(child) + 5, (byte)sibling);
            }
        }
        WriteByte(ObjectAddress(number) + 4, 0);
        WriteByte(ObjectAddress(number) + 5, 0);
    }

    private void InsertObject(ushort number, ushort destination)
    {
        if (number == 0 || destination == 0)
            throw new InvalidDataException("物体0は移動できない。");
        RemoveObject(number);
        var destinationAddress = ObjectAddress(destination);
        WriteByte(ObjectAddress(number) + 4, (byte)destination);
        WriteByte(ObjectAddress(number) + 5, ReadByte(destinationAddress + 6));
        WriteByte(destinationAddress + 6, (byte)number);
    }

    private int PropertyTableAddress(ushort number) => ReadWord(ObjectAddress(number) + 7);

    private int FirstPropertyHeader(ushort number)
    {
        var address = PropertyTableAddress(number);
        return address + 1 + 2 * ReadByte(address);
    }

    private int GetPropertyAddress(ushort number, ushort property)
    {
        if (number == 0 || property is 0 or > 31)
            return 0;
        var address = FirstPropertyHeader(number);
        while (true)
        {
            var size = ReadByte(address);
            var propertyNumber = size & 0x1f;
            if (propertyNumber == 0 || propertyNumber < property)
                return 0;
            var length = (size >> 5) + 1;
            if (propertyNumber == property)
                return address + 1;
            address += 1 + length;
        }
    }

    private ushort GetProperty(ushort number, ushort property)
    {
        var address = GetPropertyAddress(number, property);
        if (address == 0)
            return ReadWord(ObjectTableAddress + 2 * (property - 1));
        return GetPropertyLength((ushort)address) == 1 ? ReadByte(address) : ReadWord(address);
    }

    private ushort GetPropertyLength(ushort propertyAddress) =>
        propertyAddress == 0 ? (ushort)0 : (ushort)((ReadByte(propertyAddress - 1) >> 5) + 1);

    private ushort GetNextProperty(ushort number, ushort property)
    {
        var header = FirstPropertyHeader(number);
        if (property == 0)
            return (ushort)(ReadByte(header) & 0x1f);
        while (true)
        {
            var size = ReadByte(header);
            var propertyNumber = size & 0x1f;
            if (propertyNumber == 0)
                throw new InvalidDataException($"物体{number}にプロパティ{property}がない。");
            var length = (size >> 5) + 1;
            if (propertyNumber == property)
                return (ushort)(ReadByte(header + 1 + length) & 0x1f);
            header += 1 + length;
        }
    }

    private void PutProperty(ushort number, ushort property, ushort value)
    {
        var address = GetPropertyAddress(number, property);
        if (address == 0)
            throw new InvalidDataException($"物体{number}にプロパティ{property}がない。");
        var length = GetPropertyLength((ushort)address);
        if (length == 1)
            WriteByte(address, (byte)value);
        else if (length == 2)
            WriteWord(address, value);
        else
            throw new InvalidDataException("put_propは長さ1または2のプロパティにだけ使用できる。");
    }

    private void PrintObject(ushort number)
    {
        if (number == 0)
            return;
        var propertyTable = PropertyTableAddress(number);
        if (ReadByte(propertyTable) == 0)
            return;
        var text = DecodeZString(propertyTable + 1, out _);
        WriteText(text, true);
    }

    private void PrintZString(int address)
    {
        var text = DecodeZString(address, out _);
        WriteText(text, true);
    }

    private string DecodeZString(int address, out int nextAddress)
    {
        var zchars = new List<int>();
        var cursor = address;
        ushort word;
        do
        {
            word = ReadWord(cursor);
            cursor += 2;
            zchars.Add((word >> 10) & 0x1f);
            zchars.Add((word >> 5) & 0x1f);
            zchars.Add(word & 0x1f);
        } while ((word & 0x8000) == 0);
        nextAddress = cursor;

        var result = new StringBuilder();
        var alphabet = 0;
        for (var index = 0; index < zchars.Count; index++)
        {
            var zchar = zchars[index];
            if (zchar == 0)
            {
                result.Append(' ');
                alphabet = 0;
            }
            else if (zchar is >= 1 and <= 3)
            {
                if (++index >= zchars.Count)
                    break;
                var entry = 32 * (zchar - 1) + zchars[index];
                var abbreviation = ReadWord(AbbreviationsAddress + 2 * entry) * 2;
                result.Append(DecodeZString(abbreviation, out _));
                alphabet = 0;
            }
            else if (zchar == 4)
            {
                alphabet = 1;
            }
            else if (zchar == 5)
            {
                alphabet = 2;
            }
            else if (alphabet == 2 && zchar == 6)
            {
                if (index + 2 >= zchars.Count)
                    break;
                var zscii = (zchars[++index] << 5) | zchars[++index];
                result.Append(ZsciiToString((ushort)zscii));
                alphabet = 0;
            }
            else
            {
                result.Append(AlphabetCharacter(alphabet, zchar));
                alphabet = 0;
            }
        }
        return result.ToString();
    }

    private static char AlphabetCharacter(int alphabet, int zchar)
    {
        if (zchar < 6 || zchar > 31)
            return '?';
        if (alphabet == 0)
            return (char)('a' + zchar - 6);
        if (alphabet == 1)
            return (char)('A' + zchar - 6);
        const string punctuation = "0123456789.,!?_#'\"/\\-:()";
        if (zchar == 7)
            return '\n';
        return zchar >= 8 ? punctuation[zchar - 8] : ' ';
    }

    private static string ZsciiToString(ushort zscii) => zscii switch
    {
        0 => "",
        13 => "\n",
        >= 32 and <= 126 => ((char)zscii).ToString(),
        _ => "?"
    };

    private void WriteText(string english, bool translate)
    {
        if (_memoryStream is { } table)
        {
            foreach (var character in english)
                WriteMemoryStreamCharacter(table, character == '\n' ? (byte)13 : (byte)character);
            return;
        }
        FlushPrintCharacterBuffer();
        if (!_screenEnabled)
            return;
        WriteScreenText(english, translate);
    }

    private void WriteScreenText(string english, bool translate)
    {
        var fallback = translate ? _translation?.TranslateOutput(english) ?? english : english;
        WriteScreenText(english, fallback);
    }

    private void WriteScreenText(string english, string fallback)
    {
        if (_translation is null)
        {
            _host.Write(english.Replace("\n", Environment.NewLine, StringComparison.Ordinal));
            return;
        }
        if (english.Count(character => character == '\n') !=
            fallback.Count(character => character == '\n'))
        {
            FlushScreenLine();
            _host.Write(fallback.Replace("\n", Environment.NewLine, StringComparison.Ordinal));
            return;
        }
        var fallbackStart = 0;
        var start = 0;
        for (var index = 0; index < english.Length; index++)
        {
            if (english[index] != '\n')
                continue;
            var fallbackNewline = fallback.IndexOf('\n', fallbackStart);
            if (index > start)
                _screenLine.Add(new ScreenSegment(
                    english[start..index],
                    fallback[fallbackStart..fallbackNewline]));
            FlushScreenLine();
            _host.Write(Environment.NewLine);
            start = index + 1;
            fallbackStart = fallbackNewline + 1;
        }
        if (start < english.Length)
            _screenLine.Add(new ScreenSegment(english[start..], fallback[fallbackStart..]));
    }

    private void FlushScreenLine()
    {
        if (_screenLine.Count == 0)
            return;
        var english = string.Concat(_screenLine.Select(segment => segment.Text));
        var composed = _translation?.TranslateOutputLine(english) ?? english;
        if (!composed.Equals(english, StringComparison.Ordinal))
        {
            _host.Write(composed);
        }
        else
        {
            foreach (var segment in _screenLine)
                _host.Write(segment.Fallback);
        }
        _screenLine.Clear();
    }

    private void WriteCharacter(string character)
    {
        if (_memoryStream is not null || !_screenEnabled)
        {
            WriteText(character, false);
            return;
        }
        if (character.Length == 1 &&
            (character[0] is >= 'a' and <= 'z' or >= 'A' and <= 'Z' or >= '0' and <= '9' ||
             character[0] is '-' or '\''))
        {
            _printCharacterBuffer.Append(character);
            return;
        }
        var translatedWord = FlushPrintCharacterBuffer();
        if (character == " " && translatedWord)
        {
            WriteScreenText(character, "");
            return;
        }
        WriteScreenText(character, _translation?.TranslateCharacter(character) ?? character);
    }

    private bool FlushPrintCharacterBuffer()
    {
        if (_printCharacterBuffer.Length == 0)
            return false;
        var word = _printCharacterBuffer.ToString();
        _printCharacterBuffer.Clear();
        var text = _translation?.TranslateOutput(word) ?? word;
        WriteScreenText(word, text);
        return text != word;
    }

    private void WriteMemoryStreamCharacter(int table, byte value)
    {
        var length = ReadWord(table);
        WriteByte(table + 2 + length, value);
        WriteWord(table, (ushort)(length + 1));
    }

    private void SelectOutputStream(IReadOnlyList<ushort> operands)
    {
        var stream = Signed(operands[0]);
        switch (stream)
        {
            case 0: break;
            case 1: _screenEnabled = true; break;
            case -1: _screenEnabled = false; break;
            case 3:
                if (operands.Count < 2)
                    throw new InvalidDataException("出力ストリーム3には表アドレスが必要だ。");
                _memoryStream = operands[1];
                WriteWord(operands[1], 0);
                break;
            case -3: _memoryStream = null; break;
        }
    }

    private void Random(ushort rangeValue)
    {
        var range = Signed(rangeValue);
        if (range > 0)
            StoreResult((ushort)_seededRandom.Next(1, range + 1));
        else if (range < 0)
        {
            _seededRandom = new Random(-range);
            StoreResult(0);
        }
        else
        {
            _seededRandom = new Random(_random.Next());
            StoreResult(0);
        }
    }

    private void ReadCommand(ushort textBuffer, ushort parseBuffer)
    {
        ShowStatus();
        var entered = _host.ReadLine();
        if (entered is null)
        {
            _running = false;
            entered = "quit";
        }
        var input = (_translation?.TranslateInput(entered) ?? entered).ToLowerInvariant();
        _inputEchoCharacters.Clear();
        foreach (var character in input)
        {
            if (character > 0x7f)
                _inputEchoCharacters.Enqueue(character);
        }
        input = new string(input.Select(character => character <= 0x7f ? character : '?').ToArray());
        var maximum = ReadByte(textBuffer);
        if (input.Length > maximum)
            input = input[..maximum];
        for (var index = 0; index < input.Length; index++)
            WriteByte(textBuffer + 1 + index, (byte)input[index]);
        WriteByte(textBuffer + 1 + input.Length, 0);
        Tokenize(input, parseBuffer);
    }

    private void Tokenize(string input, ushort parseBuffer)
    {
        var dictionary = DictionaryAddress;
        var separatorCount = ReadByte(dictionary++);
        var separators = new HashSet<char>();
        for (var index = 0; index < separatorCount; index++)
            separators.Add((char)ReadByte(dictionary++));
        var entryLength = ReadByte(dictionary++);
        var entryCount = ReadWord(dictionary);
        dictionary += 2;

        var tokens = new List<(string Word, int Position)>();
        for (var index = 0; index < input.Length;)
        {
            if (input[index] == ' ')
            {
                index++;
                continue;
            }
            if (separators.Contains(input[index]))
            {
                tokens.Add((input[index].ToString(), index + 1));
                index++;
                continue;
            }
            var start = index;
            while (index < input.Length && input[index] != ' ' && !separators.Contains(input[index]))
                index++;
            tokens.Add((input[start..index], start + 1));
        }

        var maximumWords = ReadByte(parseBuffer);
        var count = Math.Min(maximumWords, tokens.Count);
        WriteByte(parseBuffer + 1, (byte)count);
        for (var index = 0; index < count; index++)
        {
            var token = tokens[index];
            var dictionaryEntry = FindDictionaryEntry(token.Word, dictionary, entryCount, entryLength);
            var entry = parseBuffer + 2 + 4 * index;
            WriteWord(entry, (ushort)dictionaryEntry);
            WriteByte(entry + 2, (byte)token.Word.Length);
            WriteByte(entry + 3, (byte)token.Position);
        }
    }

    private int FindDictionaryEntry(string word, int firstEntry, int entryCount, int entryLength)
    {
        var encoded = EncodeDictionaryWord(word);
        for (var index = 0; index < entryCount; index++)
        {
            var address = firstEntry + index * entryLength;
            if (ReadByte(address) == encoded[0] && ReadByte(address + 1) == encoded[1] &&
                ReadByte(address + 2) == encoded[2] && ReadByte(address + 3) == encoded[3])
                return address;
        }
        return 0;
    }

    private static byte[] EncodeDictionaryWord(string word)
    {
        var zchars = new List<int>(8);
        const string punctuation = "0123456789.,!?_#'\"/\\-:()";
        foreach (var character in word.ToLowerInvariant())
        {
            if (character == ' ')
            {
                zchars.Add(0);
            }
            else if (character is >= 'a' and <= 'z')
            {
                zchars.Add(character - 'a' + 6);
            }
            else
            {
                var punctuationIndex = punctuation.IndexOf(character);
                if (punctuationIndex >= 0)
                {
                    zchars.Add(5);
                    zchars.Add(punctuationIndex + 8);
                }
                else
                {
                    var zscii = (byte)character;
                    zchars.Add(5);
                    zchars.Add(6);
                    zchars.Add(zscii >> 5);
                    zchars.Add(zscii & 0x1f);
                }
            }
            if (zchars.Count >= 6)
                break;
        }
        if (zchars.Count > 6)
            zchars.RemoveRange(6, zchars.Count - 6);
        while (zchars.Count < 6)
            zchars.Add(5);
        var first = (ushort)((zchars[0] << 10) | (zchars[1] << 5) | zchars[2]);
        var second = (ushort)(0x8000 | (zchars[3] << 10) | (zchars[4] << 5) | zchars[5]);
        return [(byte)(first >> 8), (byte)first, (byte)(second >> 8), (byte)second];
    }

    private void ShowStatus()
    {
        FlushPrintCharacterBuffer();
        FlushScreenLine();
        var location = ReadWord(GlobalsAddress);
        if (location == 0)
            return;
        var name = DecodeObjectName(location);
        if (_translation is not null)
            name = _translation.TranslateOutput(name);
        var score = Signed(ReadWord(GlobalsAddress + 2));
        var moves = Signed(ReadWord(GlobalsAddress + 4));
        var status = _translation is null
            ? $"\n[{name}  Score {score}  Moves {moves}]\n"
            : _translation.FormatUi(
                "status.line",
                "\n［{0}　得点 {1}　手数 {2}］\n",
                name,
                score,
                moves);
        _host.Write(status);
    }

    private readonly record struct ScreenSegment(string Text, string Fallback);

    private string DecodeObjectName(ushort number)
    {
        var table = PropertyTableAddress(number);
        return ReadByte(table) == 0 ? "" : DecodeZString(table + 1, out _);
    }

    private bool VerifyChecksum()
    {
        var length = ReadWord(0x1a) * 2;
        if (length == 0 || length > _memory.Length)
            length = _memory.Length;
        var checksum = 0;
        for (var address = 0x40; address < length; address++)
            checksum = (checksum + _memory[address]) & 0xffff;
        return checksum == ReadWord(0x1c);
    }

    private ushort ReadNextWord()
    {
        var value = ReadWord(_pc);
        _pc += 2;
        return value;
    }

    private byte ReadByte(int address)
    {
        if ((uint)address >= _memory.Length)
            throw new IndexOutOfRangeException($"メモリー読込範囲外: ${address:x}");
        return _memory[address];
    }

    private ushort ReadWord(int address) => (ushort)((ReadByte(address) << 8) | ReadByte(address + 1));

    private void WriteByte(int address, byte value)
    {
        if ((uint)address >= ReadWord(0x0e))
            throw new InvalidOperationException($"静的メモリーへ書き込もうとした: ${address:x4}");
        _memory[address] = value;
    }

    private void WriteWord(int address, ushort value)
    {
        WriteByte(address, (byte)(value >> 8));
        WriteByte(address + 1, (byte)value);
    }

    private static short Signed(ushort value) => unchecked((short)value);

    private static Exception Unsupported(OpcodeClass opcodeClass, int opcode) =>
        new NotSupportedException($"未実装のVersion 3命令: {opcodeClass}:{opcode:x2}");

    private enum OpcodeClass { Zero, One, Two, Variable }

    private sealed class Frame(int returnAddress, int storeVariable, ushort[] locals)
    {
        public int ReturnAddress { get; } = returnAddress;
        public int StoreVariable { get; } = storeVariable;
        public ushort[] Locals { get; } = locals;
        public List<ushort> Stack { get; } = [];
    }
}

internal sealed class ZMachineException(string message, Exception innerException) : Exception(message, innerException);
