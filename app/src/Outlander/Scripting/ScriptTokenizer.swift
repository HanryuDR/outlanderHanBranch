//
//  File.swift
//  Outlander
//
//  Created by Joe McBride on 2/18/21.
//  Copyright © 2021 Joe McBride. All rights reserved.
//

import Foundation

enum Expression {
    case value(String)
    case function(String, String)
    indirect case expression(Expression)
}

enum ScriptTokenValue: Hashable {
    case comment(String)
    case debug(String)
    case echo(String)
    case exit
    case goto(String)
    case label(String)
    case match(String, String)
    case matchre(String, String)
    case matchwait(String)
    case pause(String)
    case put(String)
    case random(String, String)
    case save(String)
    case send(String)
    case variable(String, String)
    case waitfor(String)
    case waitforre(String)
}

extension ScriptTokenValue: CustomStringConvertible {
    var description: String {
        switch self {
        case .comment:
            return "comment"
        case .debug:
            return "debug"
        case .echo:
            return "echo"
        case .exit:
            return "exit"
        case .goto:
            return "goto"
        case .label:
            return "label"
        case .match:
            return "match"
        case .matchre:
            return "matchre"
        case .matchwait:
            return "matchwait"
        case .pause:
            return "pause"
        case .put:
            return "put"
        case .random:
            return "random"
        case .save:
            return "save"
        case .send:
            return "send"
        case .variable:
            return "variable"
        case .waitfor:
            return "waitfor"
        case .waitforre:
            return "waitforre"
        }
    }
}

protocol IScriptReaderMode: AnyObject {
    func read(_ context: ScriptTokenizerContext) -> IScriptReaderMode?
}

class ScriptTokenizerContext {
    var text: String.SubSequence
    var target: [ScriptTokenValue]

    init(_ target: [ScriptTokenValue], text: String.SubSequence) {
        self.target = target
        self.text = text
    }
}

class ScriptReaderBase<T> {
    private var modes: Stack<IScriptReaderMode>

    init(target: T) {
        modes = Stack<IScriptReaderMode>()
        self.target = target
    }

    public var target: T

    var current: IScriptReaderMode? { modes.peek() }

    public func push(_ mode: IScriptReaderMode) {
        modes.push(mode)
    }

    public func read(_ text: String) -> ScriptTokenValue? {
        guard modes.hasItems() else { return nil }

        let context = ScriptTokenizerContext([], text: text[...])

        startNewMode(context)

        afterRead()

        return context.target.first
    }

    func afterRead() {}

    func startNewMode(_ context: ScriptTokenizerContext) {
        guard modes.hasItems() else { return }

        let next = current?.read(context)

        guard let nextMode = next else {
            _ = modes.pop()
            startNewMode(context)
            return
        }

        if nextMode !== current {
            modes.push(nextMode)
            startNewMode(context)
        }
    }
}

class ScriptTokenizer: ScriptReaderBase<[ScriptTokenValue]> {
    init() {
        super.init(target: [])
        push(CommandMode())
    }

    override func afterRead() {
        push(CommandMode())
    }
}

class CommandMode: IScriptReaderMode {
    var knownCommands: [String: IScriptReaderMode?] = [
        "debug": DebugMode(),
        "echo": EchoMode(),
        "exit": ExitMode(),
        "goto": GotoMode(),
        "match": MatchMode(),
        "matchre": MatchreMode(),
        "matchwait": MatchwaitMode(),
        "pause": PauseMode(),
        "put": PutMode(),
        "random": RandomMode(),
        "save": SaveMode(),
        "send": SendMode(),
        "setvariable": VariableMode(),
        "var": VariableMode(),
        "waitfor": WaitforMode(),
        "waitforre": WaitforReMode(),
    ]

    func read(_ context: ScriptTokenizerContext) -> IScriptReaderMode? {
        let first = context.text.first
        guard first != nil else {
            return nil
        }

        if first == "#" {
            let text = context.text.parseToEnd()
            context.target.append(ScriptTokenValue.comment(String(text)))
            return nil
        }

        let result = context.text.parseWord()
        if result.count > 0 {
            if result.last == ":" {
                context.target.append(ScriptTokenValue.label(String(result.dropLast())))
                return nil
            }

            let command = String(result).lowercased()
            if let mode = knownCommands[command] {
                return mode
            } else {
                return nil
            }
        }

        guard context.text.first != nil else {
            return nil
        }

        return nil
    }
}

class DebugMode: IScriptReaderMode {
    func read(_ context: ScriptTokenizerContext) -> IScriptReaderMode? {
        context.text.consumeSpaces()
        let rest = String(context.text.parseToEnd())
        context.target.append(ScriptTokenValue.debug(rest))
        return nil
    }
}

class EchoMode: IScriptReaderMode {
    func read(_ context: ScriptTokenizerContext) -> IScriptReaderMode? {
        context.text.consumeSpaces()
        let rest = String(context.text.parseToEnd())
        context.target.append(ScriptTokenValue.echo(rest))
        return nil
    }
}

class ExitMode: IScriptReaderMode {
    func read(_ context: ScriptTokenizerContext) -> IScriptReaderMode? {
        context.target.append(ScriptTokenValue.exit)
        return nil
    }
}

class GotoMode: IScriptReaderMode {
    func read(_ context: ScriptTokenizerContext) -> IScriptReaderMode? {
        context.text.consumeSpaces()
        let rest = String(context.text.parseWord())
        context.target.append(ScriptTokenValue.goto(rest))
        return nil
    }
}

class MatchMode: IScriptReaderMode {
    func read(_ context: ScriptTokenizerContext) -> IScriptReaderMode? {
        context.text.consumeSpaces()
        let label = String(context.text.parseWord())
        context.text.consumeSpaces()
        let rest = String(context.text.parseToEnd())
        context.target.append(ScriptTokenValue.match(label, rest))
        return nil
    }
}

class MatchreMode: IScriptReaderMode {
    func read(_ context: ScriptTokenizerContext) -> IScriptReaderMode? {
        context.text.consumeSpaces()
        let label = String(context.text.parseWord())
        context.text.consumeSpaces()
        let rest = String(context.text.parseToEnd())
        context.target.append(ScriptTokenValue.matchre(label, rest))
        return nil
    }
}

class MatchwaitMode: IScriptReaderMode {
    func read(_ context: ScriptTokenizerContext) -> IScriptReaderMode? {
        context.text.consumeSpaces()
        let rest = String(context.text.parseToEnd())
        context.target.append(ScriptTokenValue.matchwait(rest))
        return nil
    }
}

class PauseMode: IScriptReaderMode {
    func read(_ context: ScriptTokenizerContext) -> IScriptReaderMode? {
        context.text.consumeSpaces()
        let rest = String(context.text.parseToEnd())
        context.target.append(ScriptTokenValue.pause(rest))
        return nil
    }
}

class PutMode: IScriptReaderMode {
    func read(_ context: ScriptTokenizerContext) -> IScriptReaderMode? {
        context.text.consumeSpaces()
        let rest = String(context.text.parseToEnd())
        context.target.append(ScriptTokenValue.put(rest))
        return nil
    }
}

class RandomMode: IScriptReaderMode {
    func read(_ context: ScriptTokenizerContext) -> IScriptReaderMode? {
        context.text.consumeSpaces()
        let min = String(context.text.parseWord())
        context.text.consumeSpaces()
        let max = String(context.text.parseToEnd())
        context.target.append(ScriptTokenValue.random(min, max))
        return nil
    }
}

class SaveMode: IScriptReaderMode {
    func read(_ context: ScriptTokenizerContext) -> IScriptReaderMode? {
        context.text.consumeSpaces()
        let rest = String(context.text.parseToEnd())
        context.target.append(ScriptTokenValue.save(rest))
        return nil
    }
}

class SendMode: IScriptReaderMode {
    func read(_ context: ScriptTokenizerContext) -> IScriptReaderMode? {
        context.text.consumeSpaces()
        let rest = String(context.text.parseToEnd())
        context.target.append(ScriptTokenValue.send(rest))
        return nil
    }
}

class VariableMode: IScriptReaderMode {
    func read(_ context: ScriptTokenizerContext) -> IScriptReaderMode? {
        context.text.consumeSpaces()
        let variable = String(context.text.parseWord())
        context.text.consumeSpaces()
        let value = String(context.text.parseToEnd())
        context.target.append(ScriptTokenValue.variable(variable, value))
        return nil
    }
}

class WaitforMode: IScriptReaderMode {
    func read(_ context: ScriptTokenizerContext) -> IScriptReaderMode? {
        context.text.consumeSpaces()
        let rest = String(context.text.parseToEnd())
        context.target.append(ScriptTokenValue.waitfor(rest))
        return nil
    }
}

class WaitforReMode: IScriptReaderMode {
    func read(_ context: ScriptTokenizerContext) -> IScriptReaderMode? {
        context.text.consumeSpaces()
        let rest = String(context.text.parseToEnd())
        context.target.append(ScriptTokenValue.waitforre(rest))
        return nil
    }
}