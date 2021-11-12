//
//  RoomChangedPlugin.swift
//  Outlander
//
//  Created by Joe McBride on 11/9/21.
//  Copyright © 2021 Joe McBride. All rights reserved.
//

import Foundation

class AutoMapperPlugin: OPlugin {
    private var host: IHost?
    private var context: GameContext
    private var movedRooms: Bool = false
    private var showAfterPrompt: Bool = false

    var name: String {
        "AutoMapper"
    }

    init(context: GameContext) {
        self.context = context
    }

    func initialize(host: IHost) {
        self.host = host
        self.host?.send(text: "#mapper reload")
    }

    func variableChanged(variable: String, value: String) {
        guard let zone = context.mapZone else {
            return
        }

        if variable == "zoneid", zone.id != value {
            context.mapZone = context.maps[value]
        }
    }

    func parse(input: String) -> String {
        input
    }

    func parse(xml: String) -> String {
        if xml.hasPrefix("<nav") {
            movedRooms = true
            return xml
        }

        if xml.hasPrefix("<compass") {
            showAfterPrompt = true
            return xml
        }

        guard movedRooms, showAfterPrompt, xml.hasPrefix("<prompt") else {
            return xml
        }

        guard let zone = context.mapZone else {
            return xml
        }

        let assignRoom = movedRooms

        showAfterPrompt = false
        movedRooms = false

        let title = context.trimmedRoomTitle()
        let desc = context.globalVars["roomdesc"] ?? ""
        let roomid = context.globalVars["roomid"]

        var room = context.findRoom(zone: zone, previousRoomId: roomid, name: title, description: desc)

        if room == nil {
            room = context.findRoomInZones(name: title, description: desc)
        }

        guard let room = room else {
            return xml
        }

        let swapped = context.swapMaps(room: room, name: title, description: desc)

        let exits = swapped.nonCardinalExists().map { $0.move }.joined(separator: ", ")
        if assignRoom {
            host?.set(variable: "roomid", value: swapped.id)
        }

        guard exits.count > 0 else {
            return xml
        }

        return "<preset id='automapper'>Mapped exits: \(exits)</preset>\n\(xml)"
    }

    func parse(text: String) -> String {
        text
    }
}

extension MapZone {
    func findRoomFuzyFrom(previousRoomId: String?, name: String, description: String, exits: [String], ignoreTransfers: Bool = false) -> MapNode? {
        guard let previousRoom = room(id: previousRoomId ?? "") else {
            return findRoom(name: name, description: description, exits: exits, ignoreTransfers: ignoreTransfers)
        }

        for arc in previousRoom.arcs {
            guard let nextRoom = room(id: arc.destination) else {
                continue
            }

            if nextRoom.matches(name: name, description: description, exits: exits, ignoreTransfers: ignoreTransfers) {
                return nextRoom
            }
        }

        return findRoom(name: name, description: description, exits: exits, ignoreTransfers: ignoreTransfers)
    }

    func findRoom(name: String, description: String, exits: [String], ignoreTransfers: Bool) -> MapNode? {
        rooms.first {
            $0.matches(name: name, description: description, exits: exits, ignoreTransfers: ignoreTransfers)
        }
    }
}

extension GameContext {
    func resetMap() {
        let title = trimmedRoomTitle()
        let description = globalVars["roomdesc"] ?? ""
        let exits = availableExits()

        if let zone = mapZone {
            if let currentRoom = zone.findRoomFuzyFrom(previousRoomId: nil, name: title, description: description, exits: exits, ignoreTransfers: true) {
                globalVars["roomid"] = currentRoom.id
            } else {
                _ = findRoomInZones(name: title, description: description)
            }
        } else {
            _ = findRoomInZones(name: title, description: description)
        }
    }

    func swapMaps(room: MapNode, name: String, description: String) -> MapNode {
        guard room.isTransfer() else {
            return room
        }

        guard let mapfile = room.transferMap else {
            return room
        }

        guard let zone = mapForFile(file: mapfile) else {
            return room
        }

        mapZone = zone

        return findRoom(zone: zone, previousRoomId: nil, name: name, description: description) ?? room
    }

    func findRoom(zone: MapZone, previousRoomId: String?, name: String, description: String) -> MapNode? {
        if let room = zone.findRoomFuzyFrom(previousRoomId: previousRoomId, name: name, description: description, exits: availableExits()) {
            return room
        }

        return findRoomInZones(name: name, description: description)
    }

    func findRoomInZones(name: String, description: String) -> MapNode? {
        let exits = availableExits()
        for (_, zone) in maps {
            if let room = zone.findRoomFuzyFrom(previousRoomId: nil, name: name, description: description, exits: exits, ignoreTransfers: true) {
                print("Found room \(room.id) in zone \(zone.id) - \(zone.name)")
                mapZone = zone
                return room
            }
        }
        return nil
    }
}
