//
//  Variables.swift
//  Outlander
//
//  Created by Joe McBride on 11/12/21.
//  Copyright © 2021 Joe McBride. All rights reserved.
//

import Foundation
import OrderedCollections
import SortedCollections

protocol IClock {
    var now: Date { get }
}

class Clock: IClock {
    private var getDate: () -> Date

    convenience init() {
        self.init { Date() }
    }

    init(_ getDate: @escaping () -> Date) {
        self.getDate = getDate
    }

    public var now: Date {
        getDate()
    }
}

public typealias VariableValueFunction = () -> String?

enum DynamicValue: CustomStringConvertible, CustomDebugStringConvertible, Hashable {
    static func == (lhs: DynamicValue, rhs: DynamicValue) -> Bool {
        lhs.rawValue == rhs.rawValue
    }

    case value(String?)
    case dynamic(VariableValueFunction)

    var rawValue: String? {
        switch self {
        case let .value(val): return val
        case let .dynamic(dynamic): return dynamic()
        }
    }

    var description: String {
        "\(String(describing: rawValue))"
    }

    var debugDescription: String {
        "[DynamicValue: \(String(describing: rawValue))]"
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(rawValue)
    }
}

class GlobalVariables: Variables {
    private var clock: IClock
    private var settings: ApplicationSettings

    static var dateFormatter = DateFormatter()

    init(events: Events, settings: ApplicationSettings, clock: IClock = Clock()) {
        self.clock = clock
        self.settings = settings
        super.init(eventKey: "ol:variable:changed", events: events)
    }

    override func addDynamics() {
        addDynamic(key: "date", value: .dynamic {
            GlobalVariables.dateFormatter.dateFormat = self.settings.variableDateFormat
            return GlobalVariables.dateFormatter.string(from: self.clock.now)
        })

        addDynamic(key: "datetime", value: .dynamic {
            GlobalVariables.dateFormatter.dateFormat = self.settings.variableDatetimeFormat
            return GlobalVariables.dateFormatter.string(from: self.clock.now)
        })

        addDynamic(key: "time", value: .dynamic {
            GlobalVariables.dateFormatter.dateFormat = self.settings.variableTimeFormat
            return GlobalVariables.dateFormatter.string(from: self.clock.now)
        })
    }
}

class Variables {
    private let lockQueue = DispatchQueue(label: "com.outlanderapp.variables.\(UUID().uuidString)", attributes: .concurrent)
    private var vars: [String: DynamicValue] = [:]
//    private var vars: SortedDictionary<String, DynamicValue> = [:]
    private var events: Events

    private var eventKey: String

    private var dynamicKeys: [String] = []

    init(eventKey: String, events: Events = NulloEvents()) {
        self.events = events
        self.eventKey = eventKey

        addDynamics()
    }

    subscript(key: String) -> String? {
        get {
            lockQueue.sync {
                vars[key]?.rawValue
            }
        }
        set {
            lockQueue.async(flags: .barrier) {
                guard !self.dynamicKeys.contains(key) else {
                    return
                }

                let res = newValue ?? ""
                guard self.vars[key]?.rawValue != res else {
                    return
                }
                self.vars[key] = .value(res)
                DispatchQueue.main.async {
                    if self.eventKey.count > 0 {
//                        print("var changed: \(key): \(res)")
                        self.events.post(self.eventKey, data: [key: res])
                    }
                }
            }
        }
    }

    var count: Int {
        lockQueue.sync {
            vars.count
        }
    }

    func removeValue(forKey key: String) {
        lockQueue.async(flags: .barrier) {
            self.vars.removeValue(forKey: key)
        }
    }

    func removeAll() {
        lockQueue.sync(flags: .barrier) {
            vars.removeAll()
            addDynamics()
        }
    }

    func keysAndValues() -> [String: String] {
        lockQueue.sync(flags: .barrier) {
            Dictionary(uniqueKeysWithValues: vars.sorted(by: { $0.key < $1.key }).map { key, value in (key, value.rawValue ?? "") })
        }
    }

    func sorted() -> [(String, String)] {
        lockQueue.sync(flags: .barrier) {
            vars.sorted(by: { $0.key < $1.key }).map { key, value in (key, value.rawValue ?? "") }
        }
    }

    var keys: [String] {
        lockQueue.sync(flags: .barrier) {
            vars.map { $0.key }.sorted(by: { $0.count > $1.count })
        }
        // return vars.map { $0.key }.sorted(by: { $0.count > $1.count })
    }

    func addDynamic(key: String, value: DynamicValue) {
        dynamicKeys.append(key)
        vars[key] = value
    }

    open func addDynamics() {}
}

struct VariableSetting {
    var token: String
    var values: (String) -> String?
}

class VariableContext {
    var settings: [VariableSetting] = []

    var keys: [String] {
        Array(Set(settings.map { $0.token }))
    }

    func add(_ token: String, values: @escaping ((String) -> String?)) {
        settings.append(VariableSetting(token: token, values: values))
    }
}

class VariableReplacer {
    func replace(_ input: String, globalVars: Variables) -> String {
        let context = VariableContext()
        context.add("$", values: { key in globalVars[key] })
        return replace(input, context: context)
    }

    func replace(_ input: String, context: VariableContext) -> String {
        guard hasPotentialVars(input, context: context) else {
            return input
        }

        var result = replaceIndexedVars(input, context: context)

        func doReplace() {
            for setting in context.settings {
                simplify(prefix: setting.token, target: &result, value: setting.values)
            }
        }

        let max = 15
        var count = 0
        var last = result

        repeat {
            doReplace()
            last = result
            count += 1
        } while count < max && last != result && hasPotentialVars(result, context: context)

        return result
    }

    func replaceIndexedVars(_ result: String, context: VariableContext) -> String {
        guard result.index(of: "[") != nil || result.index(of: "(") != nil else {
            return result
        }

        let tokens = VariableTokenizer().read(result)
        guard tokens.count > 0 else {
            return result
        }

        var results: [String] = []
        for v in tokens {
            switch v {
            case let .value(val):
                results.append(val)
            case let .indexed(varname, index):
                let name = replace(varname, context: context)
                let idx = replace(index, context: context)

                guard let number = Int(idx) else {
                    results.append("\(name)[\(idx)]")
                    continue
                }

                let list = name.components(separatedBy: "|")
                guard number > -1, number < list.count else {
                    results.append("\(name)[\(idx)]")
                    continue
                }

                let val = list[number]
                results.append(val)
            }
        }

        return results.joined(separator: "")
    }

    func hasPotentialVars(_ input: String, context: VariableContext) -> Bool {
        for key in context.keys {
            if input.range(of: key) != nil {
                return true
            }
        }

        return false
    }

    private func simplify(prefix: String, target: inout String, value: (String) -> String?) {
        guard target.contains(prefix) else {
            return
        }

        let regexChecks = [
            "([\(prefix)]([a-zA-Z0-9_\\-.]+))",
            "([\(prefix)]([a-zA-Z0-9_\\-]+))",
            "([\(prefix)]([a-zA-Z0-9]+))",
        ]

        func doReplace() {
            for pattern in regexChecks {
                guard let regex = RegexFactory.get(pattern) else {
                    return
                }
                let matches = regex.allMatches(&target)
                for match in matches.reversed() {
                    guard let _ = match.valueAt(index: 1), let key = match.valueAt(index: 2) else {
                        continue
                    }

                    guard let val = value(key) else {
                        continue
                    }

                    guard let range = match.rangeOf(index: 0) else {
                        continue
                    }

                    target.replaceSubrange(range, with: val)
                }
            }
        }

        let max = 15
        var count = 0

        repeat {
            doReplace()
            count += 1
        } while count < max && target.contains(prefix)
    }
}