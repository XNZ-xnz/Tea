import Foundation

/// Valve KeyValues 文本格式（VDF/ACF）解析器。
/// 覆盖 Steam 库文件实际用到的子集：引号键值、嵌套块、// 注释、\ 转义、[$条件] 忽略。
public enum KeyValues {
    public indirect enum Value: Equatable, Sendable {
        case string(String)
        case dict([String: Value])

        public var stringValue: String? {
            if case .string(let s) = self { return s }
            return nil
        }

        public var dictValue: [String: Value]? {
            if case .dict(let d) = self { return d }
            return nil
        }

        /// 大小写不敏感取键（Steam 文件里 StateFlags/stateflags 混用）
        public subscript(key: String) -> Value? {
            guard case .dict(let d) = self else { return nil }
            if let exact = d[key] { return exact }
            let lower = key.lowercased()
            return d.first { $0.key.lowercased() == lower }?.value
        }
    }

    public enum ParseError: Error, LocalizedError {
        case unexpectedEnd
        case unexpectedToken(String, line: Int)

        public var errorDescription: String? {
            switch self {
            case .unexpectedEnd: return "VDF 文件不完整（意外结束）"
            case .unexpectedToken(let t, let line): return "VDF 第 \(line) 行有意外符号：\(t)"
            }
        }
    }

    /// 解析整份文档，返回顶层（通常单键，如 "libraryfolders" / "AppState"）。
    public static func parse(_ text: String) throws -> Value {
        var tokens = Tokenizer(text)
        var root: [String: Value] = [:]
        while let key = try tokens.next() {
            guard case .string(let k) = key else {
                throw ParseError.unexpectedToken(key.display, line: tokens.line)
            }
            root[k] = try parseValue(&tokens)
        }
        return .dict(root)
    }

    /// 便捷入口：文件 → 顶层第一个块的内容
    public static func parseFile(_ url: URL) throws -> Value {
        let text = try String(contentsOf: url, encoding: .utf8)
        return try parse(text)
    }

    static func parseValue(_ tokens: inout Tokenizer) throws -> Value {
        guard let token = try tokens.next() else { throw ParseError.unexpectedEnd }
        switch token {
        case .string(let s):
            return .string(s)
        case .open:
            var dict: [String: Value] = [:]
            while true {
                guard let t = try tokens.next() else { throw ParseError.unexpectedEnd }
                if case .close = t { return .dict(dict) }
                guard case .string(let key) = t else {
                    throw ParseError.unexpectedToken(t.display, line: tokens.line)
                }
                dict[key] = try parseValue(&tokens)
            }
        case .close:
            throw ParseError.unexpectedToken("}", line: tokens.line)
        }
    }

    // MARK: - 词法

    enum Token {
        case string(String)
        case open, close

        var display: String {
            switch self {
            case .string(let s): return "\"\(s)\""
            case .open: return "{"
            case .close: return "}"
            }
        }
    }

    struct Tokenizer {
        let chars: [Character]
        var index = 0
        var line = 1

        init(_ text: String) { chars = Array(text) }

        mutating func next() throws -> Token? {
            skipWhitespaceAndComments()
            guard index < chars.count else { return nil }
            let c = chars[index]
            switch c {
            case "{": index += 1; return .open
            case "}": index += 1; return .close
            case "\"": return .string(try readQuoted())
            case "[":
                // 条件标记 [$WIN32] 之类：跳到 ] 后继续
                while index < chars.count, chars[index] != "]" { index += 1 }
                index += 1
                return try next()
            default:
                // 裸词（无引号键值，老格式偶见）
                var word = ""
                while index < chars.count, !chars[index].isWhitespace,
                      !["{", "}", "\""].contains(chars[index]) {
                    word.append(chars[index]); index += 1
                }
                return .string(word)
            }
        }

        mutating func readQuoted() throws -> String {
            index += 1 // 开引号
            var out = ""
            while index < chars.count {
                let c = chars[index]
                if c == "\\", index + 1 < chars.count {
                    let n = chars[index + 1]
                    switch n {
                    case "n": out.append("\n")
                    case "t": out.append("\t")
                    case "\\": out.append("\\")
                    case "\"": out.append("\"")
                    default: out.append(n)
                    }
                    index += 2
                    continue
                }
                if c == "\"" { index += 1; return out }
                if c == "\n" { line += 1 }
                out.append(c)
                index += 1
            }
            throw ParseError.unexpectedEnd
        }

        mutating func skipWhitespaceAndComments() {
            while index < chars.count {
                let c = chars[index]
                if c == "\n" { line += 1; index += 1; continue }
                if c.isWhitespace { index += 1; continue }
                if c == "/", index + 1 < chars.count, chars[index + 1] == "/" {
                    while index < chars.count, chars[index] != "\n" { index += 1 }
                    continue
                }
                break
            }
        }
    }
}
