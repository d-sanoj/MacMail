import AppKit

class TraitSender: NSObject {
    @objc var tag: Int
    init(tag: Int) { self.tag = tag }
}

let sender = TraitSender(tag: 2)
print("Tag: \(sender.tag)")
