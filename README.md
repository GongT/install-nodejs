# install node.js
Install pnpm (and nodejs) into `/usr/local/share/pnpm`
* auto configure npm to use `/usr/local/share/pnpm`, prevent it using `/usr/local/bin`
* create & append required environment variables
* rebuild global dependencies

# Support
support: **64BIT ONLY** linux & cygwin & Mac OS & WSL

dependencies: wget & xz & sed & sort & grep  
**and standard gnu-utils on Mac**

# Usage
**latest:**
```bash
wget --quiet -O - https://raw.githubusercontent.com/GongT/install-nodejs/master/install.sh | bash -s -
```

also can upgrade node to latest stable version.

**any major version: (0.x not supported)**
```bash
wget --quiet -O - https://raw.githubusercontent.com/GongT/install-nodejs/master/install.sh | bash -s - 12
```
