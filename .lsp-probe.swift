struct Probe {
    let value: Int
    func doubled() -> Int { value * 2 }
}

let probe = Probe(value: 21)
let result = probe.doubled()