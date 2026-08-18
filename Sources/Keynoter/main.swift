import Foundation

Console.configure()

let session = Session()
let repl = REPL(session: session)
await repl.run()
