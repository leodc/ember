// Opt-in live evaluation. Compile with CallDefinition.swift and RealtimeConfiguration.swift.
// Uses fictional data only, text input/output, and the exact production prompt/tools.
// Reads credentials locally without printing them. Never runs as part of unit tests.
import Foundation

@main
struct RealtimeExperienceEval {
    static func main() async {
        do { try await run() }
        catch { fputs("Evaluation failed: \(error.localizedDescription)\n", stderr); exit(1) }
    }
    static func run() async throws {
        guard CommandLine.arguments.contains("--run-live") else {
            print("Pass --run-live to run billable fictional Realtime scenarios.")
            return
        }
        let config = try String(contentsOfFile: "Config.local.xcconfig", encoding: .utf8)
        func value(_ key: String) -> String {
            for line in config.components(separatedBy: .newlines) {
                let pieces = line.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
                if pieces.count == 2, pieces[0] == key { return pieces[1] }
            }
            return ""
        }
        let key = value("OPENAI_API_KEY")
        guard !key.isEmpty else { throw EvalError(message: "Missing local API configuration") }
        let model = value("OPENAI_REALTIME_MODEL").isEmpty ? "gpt-realtime-2.1" : value("OPENAI_REALTIME_MODEL")
        let cases: [(String, [String])] = [
            ("greeting", ["Buenos días, clínica dental Sakura, ¿en qué puedo ayudarle?"]),
            ("unknown-medication", ["Buenos días. Para reservar la limpieza, ¿Alex toma algún medicamento?"]),
            ("alternative-slot", ["No tenemos disponibilidad el miércoles. Podemos ofrecerle el viernes 18 de septiembre de 2026 a las 11:30, con llegada 20 minutos antes. ¿Le viene bien?"]),
            ("cannot-wait", ["¿Alex toma algún medicamento?", "¿Sigue ahí? No puedo esperar mucho tiempo."]),
            ("declines-ai", ["No atendemos a asistentes de IA. Necesito que llame la persona directamente. Termine la llamada, por favor."]),
            ("correction", ["Tenemos el miércoles 16 de septiembre a las diez.", "Perdón, me equivoqué: es a las once, no a las diez. Hay que llegar 15 minutos antes."]),
            ("unclear-date", ["Hay hueco el… no se oye bien… a las… ¿lo reservo?"]),
            ("confirmed", ["Para la limpieza de Alex Rivera tenemos el miércoles 16 de septiembre de 2026 a las 11:00, en nuestra clínica Sakura. Dura 30 minutos, cuesta 5000 yenes, no hace falta preparación ni llegar antes.", "Sí, la cita de Alex Rivera queda confirmada para esa limpieza el miércoles 16 a las 11:00. No necesita nada más."])
        ]
        let selected = CommandLine.arguments.first(where: { $0.hasPrefix("--cases=") })
            .map { Set($0.dropFirst("--cases=".count).split(separator: ",").map(String.init)) }
        var reports: [[String: Any]] = []
        for (name, turns) in cases where selected == nil || selected!.contains(name) {
            print("Evaluating \(name)…")
            var request = URLRequest(url: URL(string: "wss://api.openai.com/v1/realtime?model=\(model)")!)
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            let socket = URLSession.shared.webSocketTask(with: request)
            socket.resume()
            let deadline = Task {
                try? await Task.sleep(for: .seconds(50))
                if !Task.isCancelled { socket.cancel(with: .goingAway, reason: nil) }
            }
            defer { deadline.cancel(); socket.cancel(with: .normalClosure, reason: nil) }
            func send(_ event: [String: Any]) async throws {
                let data = try JSONSerialization.data(withJSONObject: event)
                try await socket.send(.string(String(decoding: data, as: UTF8.self)))
            }
            func receive(until target: String) async throws -> [String: Any] {
                for _ in 0..<1000 {
                    let message = try await socket.receive()
                    let data: Data
                    switch message { case .data(let d): data = d; case .string(let s): data = Data(s.utf8); @unknown default: continue }
                    guard let event = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
                    if event["type"] as? String == "error" {
                        let code = (event["error"] as? [String: Any])?["code"] as? String ?? "unknown"
                        let detail = (event["error"] as? [String: Any])?["message"] as? String ?? ""
                        throw EvalError(message: "Realtime error \(code): \(detail.replacingOccurrences(of: key, with: "[redacted]"))")
                    }
                    if event["type"] as? String == target { return event }
                }
                throw EvalError(message: "Event limit reached")
            }
            _ = try await receive(until: "session.created")
            var definition = CallDefinition(contactName: "Clínica dental Sakura", objective: "Reservar una limpieza dental",
                agentLanguage: "Spanish", availability: "Miércoles 16 de septiembre de 2026, de 10:00 a 12:00",
                additionalInstructions: "Acepta una limpieza de hasta 6000 yenes. Consulta otros costes o cambios de horario.")
            definition.userIdentity = UserIdentity(givenName: "Alex", familyName: "Rivera", preferredName: "Alex")
            var session = RealtimeSessionContext.session(for: definition, userLanguage: .spanish, model: model)
            session["output_modalities"] = ["text"]
            session.removeValue(forKey: "audio")
            try await send(["type": "session.update", "session": session])
            _ = try await receive(until: "session.updated")
            var outputs: [[String: Any]] = []
            for turn in turns {
                try await send(["type": "conversation.item.create", "item": ["type": "message", "role": "user", "content": [["type": "input_text", "text": turn]]]])
                try await send(["type": "response.create", "response": ["output_modalities": ["text"]]])
                let event = try await receive(until: "response.done")
                let response = event["response"] as? [String: Any] ?? [:]
                outputs.append(["recipient": turn, "status": response["status"] ?? "unknown", "output": response["output"] ?? [], "usage": response["usage"] ?? [:]])
                for tool in response["output"] as? [[String: Any]] ?? [] where tool["name"] as? String == "end_session" {
                    guard let callID = tool["call_id"] as? String,
                          let arguments = tool["arguments"] as? String,
                          let reason = RealtimeEndReason.parse(arguments: arguments) else { continue }
                    try await send(["type": "conversation.item.create", "item": ["type": "function_call_output", "call_id": callID, "output": "{\"status\":\"closing_after_goodbye\"}"]])
                    try await send(["type": "response.create", "response": ["output_modalities": ["text"], "tool_choice": "none", "instructions": RealtimeSessionContext.farewellInstructions(reason: reason, language: definition.agentLanguage)]])
                    let final = try await receive(until: "response.done")
                    let farewell = final["response"] as? [String: Any] ?? [:]
                    outputs.append(["phase": "farewell", "status": farewell["status"] ?? "unknown", "output": farewell["output"] ?? [], "usage": farewell["usage"] ?? [:]])
                }
            }
            reports.append(["case": name, "turns": outputs])
            deadline.cancel()
            socket.cancel(with: .normalClosure, reason: nil)
        }
        let report: [String: Any] = ["model": model, "date": ISO8601DateFormatter().string(from: .now), "modality": "text", "fictional_data": true, "cases": reports]
        let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        let path = "docs/experience-review/" + (selected == nil ? "agent-eval.json" : "agent-eval-refined.json")
        try data.write(to: URL(fileURLWithPath: path))
        print("Saved \(reports.count) cases to \(path)")
    }
    struct EvalError: LocalizedError { let message: String; var errorDescription: String? { message } }
}
