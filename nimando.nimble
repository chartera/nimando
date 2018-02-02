srcDir        = "src"
binDir        = "bin"
bin           = @["nimando"]

# Package

version       = "0.1.0"
author        = "Nael Tasmim"
description   = "A TCP commander query replicator"
license       = "BSD"

# Dependencies

requires "nim >= 0.17.2", "crpl", "protocol"
