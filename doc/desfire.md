# Notes on MIFARE DESFire
<a id="Top"></a>

# Table of Contents

- [Notes on MIFARE DESFire](#notes-on-mifare-desfire)
- [Table of Contents](#table-of-contents)
  - [Documentation](#documentation)
  - [Source code](#source-code)
  - [Communication channel with a card](#communication-channel-with-a-card)
  - [Card architecture](#card-architecture)
  - [Card structure](#card-structure)
  - [DESFire Light](#desfire-light)
  - [How to](#how-to)
    - [How to get card UID](#how-to-get-card-uid)
    - [How to get/set default communication channel settings](#how-to-getset-default-communication-channel-settings)
    - [How to guess default communication channel settings](#how-to-guess-default-communication-channel-settings)
    - [How to try communication channel settings](#how-to-try-communication-channel-settings)
    - [How to look at the application list on the card](#how-to-look-at-the-application-list-on-the-card)
    - [How to look/dump files from the application file list](#how-to-lookdump-files-from-the-application-file-list)
    - [How to change key](#how-to-change-key)
    - [How to create the application](#how-to-create-the-application)
    - [How to create files](#how-to-create-files)
    - [How to delete files](#how-to-delete-files)
    - [How to read/write files](#how-to-readwrite-files)
    - [How to work with value files](#how-to-work-with-value-files)
    - [How to work with transaction mac](#how-to-work-with-transaction-mac)
    - [How to switch DESFire Light to LRP mode](#how-to-switch-desfire-light-to-lrp-mode)


## Documentation
^[Top](#top)

[DESFire Light datasheet MF2DL(H)x0](https://www.nxp.com/docs/en/data-sheet/MF2DLHX0.pdf)

[Features and Hints AN12343](https://www.nxp.com/docs/en/application-note/AN12343.pdf)

[Quick Start Guide AN12341](https://www.nxp.com/docs/en/application-note/AN12341.pdf)

[LRP Specification](https://www.nxp.com/docs/en/application-note/AN12304.pdf)

[NTAG 424 DNA NT4H2421Gx](https://www.nxp.com/docs/en/data-sheet/NT4H2421Gx.pdf)

[NTAG features and hints - LRP mode](https://www.nxp.com/docs/en/application-note/AN12321.pdf)

[ev2 samples AN12196](https://www.nxp.com/docs/en/application-note/AN12196.pdf)

[MIFARE Application Directory AN10787](https://www.nxp.com/docs/en/application-note/AN10787.pdf)

[Symmetric key diversifications AN10922](https://www.nxp.com/docs/en/application-note/AN10922.pdf)

## Source code
^[Top](#top)

[desfire_crypto from proxmark3](https://github.com/RfidResearchGroup/proxmark3/blob/master/armsrc/desfire_crypto.c)

[libfreefare](https://github.com/nfc-tools/libfreefare)

[desfire-tools-for-android](https://github.com/skjolber/desfire-tools-for-android)

[nfcjlib](https://github.com/andrade/nfcjlib/)

[java-card-desfire-emulation](https://github.com/gathigai/java-card-desfire-emulation)

[ChameleonMiniDESFireStack](https://github.com/maxieds/ChameleonMiniDESFireStack/)

[LRP/ev2 nfc-ev2-crypto](https://github.com/icedevml/nfc-ev2-crypto)

## Communication channel with a card
^[Top](#top)

The card can work with a combination of: key type - command set - secure channel - communication mode

*key types:*

**des** - 8-byte key. can be present in a form of **2tdea** key with length 16 bytes by duplicating contents twice.

**2tdea** - 16-byte key

**3tdea** - 24-byte key. can be disabled on the card level.

**aes** - 16-byte AES-128 key

*command sets:*

**native** - raw commands

**native iso** - wraps raw commands into the ISO APDU. **CLA** = 0x90, **INS** = command code, **data** = the remaining data from raw command

**iso** - works only for some commands: ISO select by ISO ID (if enabled), authenticate, read and write in the **plain** mode, read in the **mac** mode

*secure channels:*

**d40** - old secure channel that can work only with **des** and **2tdea** keys

**ev1** - secure channel that can work with all the keys: **des**, **2tdea**, **3tdea**, **aes**

**ev2** - the newest channel that can work with **aes** key only

*communication modes*

**plain** - just plain data between card and reader

**maced** - mac applied to request/response/both (may be sent or not)

**encrypted** - encrypted data in the request/response/both in the ev2 channel data signed with mac.

## Card architecture
^[Top](#top)

The card has several applications on it and the applications have files and some other objects.

Each card has a master application with AID 0x000000 that saves the card's configuration.

Master application has many keys with different purposes, but commands show that there is only one key - card master key.

Each application may have its own key type and set of keys. Each file can only have links to these keys in its access rights.

## Card structure
^[Top](#top)

- Application
- Application number: 1 byte
- Application ISO number: if set at the time of application creation. It can be selected by this ID in the ISO command set.
- Application DF name: 1-16 chars. It can be selected by this name in the ISO command set.
- Key settings: number of keys, key type, key config (what can do/not user with keys)
- Keys: up to 14 keys (indexes 0..d)
- Key versions: key version of corresponding key
- Files:
  - File number: 1 byte
  - File ISO number: should be present if and only if application created with ISO number.
  - File type: standard, backup, value, cyclic record, linear record, transaction mac
  - Some settings that belong to file type (size for standard file for example)
  - File communication mode: plain/maced/encrypted
  - File access right: there are 4 modes: read/write/read-write/change settings. And each mode access can be: key0..keyD, E - free access, F - deny access

## DESFire Light
^[Top](#top)

The card has one preinstalled master file (ISO ID 0x3f00) and one application (0xdf01)

In the application, there are 6 files:

- 0x00 Standard data file with size 256 bytes
- 0x01 Cyclic record file with 5 records with size 16 bytes each
- 0x03 Value file
- 0x04 Standard data file with size 256 bytes
- 0x0f Transaction MAC file with size 256 bytes
- 0x1f Standard data file with size 32 bytes. Used for FCI.

User can't create/delete files (except Transaction MAC file).

ISO file IDs, the other files and application parameters can be changed via SetConfiguration command only.

The card has two secure channels: EV2 and LRP. By default, EV2 is on. LRP can be switched on by issuing SetConfiguration command and after that, it can't be switched off.

Application on the card can't be selected by DESFire native select. Needs to issue ISO select command. All the commands that can work in LRP channel have **--appisoid** option

Transaction MAC file - the only file that can be created and deleted. By default, all transaction operations (operations with Value and Record file) need to issue CommitReaderID command.  
So (to fast check- it is needed to delete this file) it has default file id - 0x0f.

FCI sends from card to reader after selecting the application (df01 by default)

If it needs to have more space for FCI - just change the ID of one of the bigger files to 0x1f (and the current ID to something else) via SetConfiguration command.

## How to


### How to get card UID
^[Top](#top)

The card can return UID in encrypted communication mode. Needs to authenticate with any key from the card.

`hf mfdes getuid` - authenticate with default key

`hf mfdes getuid -s d40` - via d40 secure channel

`hf mfdes getuid -s ev2 -t aes -k 11223344556677889900112233445566` - via ev2 secure channel with specified aes key

### How to get/set default communication channel settings
^[Top](#top)

All the commands use these settings by default if a more important setting is not specified in the command line.

`hf mfdes default` - get channel settings

`hf mfdes default -n 1 -t aes` - set key number 1 and key type aes

### How to guess default communication channel settings
^[Top](#top)

`hf mfdes detect` - simply detect key for master application (PICC level)

`hf mfdes detect --save` - detect key and save to defaults. look after to output of `hf mfdes default`

`hf mfdes detect -s d40` - detect via channel d40

`hf mfdes detect --dict mfdes_default_keys` - detect key with help of dictionary file

`hf mfdes detect --aid 123456 -n 2` - detect key 2 from application with AID 123456

### How to try communication channel settings
^[Top](#top)

`hf mfdes auth -n 0 -t des -k 1122334455667788 --aid 123456` - try application 123456 master key

`hf mfdes auth -n 0 -t aes --save` - try PICC AES master key and save the configuration to defaults if authentication succeeds

### How to look at the application list on the card
^[Top](#top)

`hf mfdes lsapp --no-auth` - show applications list without authentication

`hf mfdes lsapp` - show applications list with authentication from default settings

`hf mfdes lsapp --files` - show applications list with their files

`hf mfdes getaids --no-auth` - this command can return a simple AID list if it is enabled in the card settings

### How to look/dump files from the application file list
^[Top](#top)

`hf mfdes lsfiles --aid 123456 -t aes` - file list for application 123456 with aes key

`hf mfdes dump --aid 123456` - shows files and their contents from application 123456

### How to change key
^[Top](#top)

Changing key algorithm can be done only in one case - change card master key.

Key algorithm for application can be chosen only on its creation.

`hf mfdes changekey -t des --newalgo aes --newkey 11223344556677889900112233445566 --newver a5` - change picc master key from des default to aes

`hf mfdes changekey --aid 123456 -t des -n 0 -k 5555555555555555 --newkey 1122334455667788` - change application master key from one key to another

`hf mfdes changekey --aid 123456 -t des -n 0 --newkeyno 1 --oldkey 5555555555555555 --newkey 1122334455667788` - change key 1 with authentication with key 0 (app master key)

### How to create the application
^[Top](#top)

`hf mfdes createapp --aid 123456 --fid 2345 --dfname aid123456 --dstalgo aes` - create an application with ISO file ID, df name, and key algorithm AES

`hf mfdes createapp --aid 123456` - create an application 123456 with DES key algorithm and without ISO file ID. in this case, iso file id can't be provided for application's files

### How to create files
^[Top](#top)

`hf mfdes createfile --aid 123456 --fid 01 --isofid 0001 --size 000010` - create standard file with ISO ID and default access settings

`hf mfdes createfile --aid 123456 --fid 01 --isofid 0001 --size 000010 --backup` - create backup file

Create standard file with mac access mode and specified access settings. access settings can be changed later with command `hf mfdes chfilesettings`

`hf mfdes createfile --aid 123456 --fid 01 --isofid 0001 --size 000010 --amode mac --rrights free --wrights free --rwrights free --chrights key0`

`hf mfdes createvaluefile --aid 123456 --fid 01 --isofid 0001 --lower 00000010 --upper 00010000 --value 00000100` - create value file (see [How to work with value files](#how-to-work-with-value-files) for detailed examples)

`hf mfdes createrecordfile --aid 123456 --fid 01 --isofid 0001 --size 000010 --maxrecord 000010` - create linear record file

`hf mfdes createrecordfile --aid 123456 --fid 01 --isofid 0001 --size 000010 --maxrecord 000010 --cyclic` - create cyclic record file

`hf mfdes createmacfile --aid 123456 --fid 01 --rawrights 0FF0 --mackey 00112233445566778899aabbccddeeff --mackeyver 01` - create transaction mac file

### How to delete files
^[Top](#top)

`hf mfdes deletefile --aid 123456 --fid 01` - delete file

### How to read/write files
^[Top](#top)

*read:*

`hf mfdes read --aid 123456 --fid 01` - autodetect file type (with `hf mfdes getfilesettings`) and read its contents

`hf mfdes read --aid 123456 --fid 01 --type record --offset 000000 --length 000001` - read one last record from a record file

*read via ISO command set:*

Here it is needed to specify the type of the file because there is no `hf mfdes getfilesettings` in the ISO command set

`hf mfdes read --aid 123456 --fileisoid 1000 --type data -c iso` - select application via native command and then read file via ISO

`hf mfdes read --appisoid 0102 --fileisoid 1000 --type data -c iso` - select all via ISO commands and then read

`hf mfdes read --appisoid 0102 --fileisoid 1100 --type record -c iso --offset 000005 --length 000001` - read one record (number 5) from file ID 1100 via ISO command set

`hf mfdes read --appisoid 0102 --fileisoid 1100 --type record -c iso --offset 000005 --length 000000` - read all the records (from 5 to 1) from file ID 1100 via ISO command set

*write:*

`hf mfdes write --aid 123456 --fid 01 -d 01020304` - autodetect file type (with `hf mfdes getfilesettings`) and write data with offset 0

`hf mfdes write --aid 123456 --fid 01 --type data -d 01020304 --commit` - write backup data file and commit

`hf mfdes write --aid 123456 --fid 01 --type value -d 00000001` increment value file (deprecated, use `hf mfdes value` command)

`hf mfdes write --aid 123456 --fid 01 --type value -d 00000001 --debit` decrement value file (deprecated, use `hf mfdes value` command)

For modern value file operations, see [How to work with value files](#how-to-work-with-value-files)

`hf mfdes write --aid 123456 --fid 01 --type record -d 01020304` write data to a record file

`hf mfdes write --aid 123456 --fid 01 --type record -d 01020304 --updaterec 0` update record 0 (latest) in the record file.

*write via iso command set:*

`hf mfdes write --appisoid 1234 --fileisoid 1000 --type data -c iso -d 01020304` write data to std/backup file via ISO command set

`hf mfdes write --appisoid 1234 --fileisoid 2000 --type record -c iso -d 01020304` send record to record file via ISO command set

*transactions:*

For more detailed samples look at the next howto.

`hf mfdes write --aid 123456 --fid 01 -d 01020304 --readerid 010203` write data to the file with CommitReaderID command before and CommitTransaction after write

### How to work with value files
^[Top](#top)

Value files are specialized files designed for storing and manipulating monetary values or counters. They provide atomic operations for incrementing (credit) and decrementing (debit) values with built-in limits and security features.

**Key Features:**
- 32-bit value storage (represented internally as unsigned)
- Lower and upper limits to prevent underflow/overflow
- Atomic operations with automatic transaction commit
- Transaction logging support
- Secure communication modes (plain, MAC, encrypted)

**Value File Structure:**
- Current value: 32-bit value
- Lower limit: minimum allowed value (prevents underflow)
- Upper limit: maximum allowed value (prevents overflow)

**Access Rights:**
Value files use four access right categories:
- **Read**: Required to get the current value (`hf mfdes value --op get`)
- **Write**: Required for debit operations (`hf mfdes value --op debit`)
- **Read/Write**: Required for credit operations (`hf mfdes value --op credit`)
- **Change**: Required to modify file settings or delete the file

Access rights can be set to:
- `key0` through `keyE`: Requires authentication with the specified key
- `free`: No authentication required
- `deny`: Operation is forbidden

*Create value file:*

Creating a Bitcoin wallet on your DESFire card:
```
pm3 --> hf mfdes createapp --aid 425443 --ks1 0B --ks2 0E
[+] Desfire application 425443 successfully created

pm3 --> hf mfdes createvaluefile --aid 425443 --fid 01 --lower 00000000 --upper 01406F40 --value 00000032
[=] ---- Create file settings ----
[+] File type        : Value
[+] File number      : 0x01 (1)
[+] File comm mode   : Plain
[+] Additional access: No
[+] Access rights    : EEEE
[+]   read......... free
[+]   write........ free
[+]   read/write... free
[+]   change....... free
[=] Lower limit... 0 / 0x00000000
[=] Upper limit... 21000000 / 0x01406F40
[=] Value............ 50 / 0x00000032
[=] Limited credit... 0 - disabled
[=] GetValue access... Not Free
[+] Value file 01 in the app 425443 created successfully
```
This creates a DESFire Bitcoin wallet with:
- Application ID 0x425443 (ASCII "BTC")
- File ID 0x01 for the wallet
- Lower limit: 0 BTC (no overdrafts in crypto)
- Upper limit: 21,000,000 BTC (respecting Satoshi's vision)
- Initial value: 50 BTC (the original block reward)

Creating the infamous Pizza Day wallet:
```
pm3 --> hf mfdes createvaluefile --aid 425443 --fid 02 --lower 00000000 --upper 01406F40 --value 00002710
[=] ---- Create file settings ----
[+] File type        : Value
[+] File number      : 0x02 (2)
[+] File comm mode   : Plain
[+] Additional access: No
[+] Access rights    : EEEE
[+]   read......... free
[+]   write........ free
[+]   read/write... free
[+]   change....... free
[=] Lower limit... 0 / 0x00000000
[=] Upper limit... 21000000 / 0x01406F40
[=] Value............ 10000 / 0x00002710
[=] Limited credit... 0 - disabled
[=] GetValue access... Not Free
[+] Value file 02 in the app 425443 created successfully
```
This creates a wallet pre-loaded with 10,000 BTC (historical exchange rate: 2 pizzas)

*Value file operations:*

Check your Bitcoin balance:
```
pm3 --> hf mfdes value --aid 425443 --fid 01 --op get
[+] Value: 50 (0x00000032)

pm3 --> hf mfdes value --aid 425443 --fid 01 --op get -m mac
[+] Value: 50 (0x00000032)
```

Loading Bitcoin IOUs onto your card:
```
pm3 --> hf mfdes value --aid 425443 --fid 01 --op credit -d 00000019
[+] Value changed successfully

pm3 --> hf mfdes value --aid 425443 --fid 01 --op get
[+] Value: 75 (0x0000004b)
```
Card now holds 75 BTC in IOUs ($9,000,000 in debt obligations)

Buying coffee with Bitcoin IOUs:
```
pm3 --> hf mfdes value --aid 425443 --fid 01 --op debit -d 00000001
[+] Value changed successfully  # You now owe the coffee shop $120,000

pm3 --> hf mfdes value --aid 425443 --fid 01 --op get
[+] Value: 74 (0x0000004a)  # Remaining debt capacity
```

The legendary Pizza Day recreation:
```
pm3 --> hf mfdes value --aid 425443 --fid 02 --op debit -d 00002710
[+] Value changed successfully  # You now owe Papa John's $1.2 billion

pm3 --> hf mfdes value --aid 425443 --fid 02 --op get
[+] Value: 0 (0x00000000)  # Card empty, bankruptcy imminent
```

*Communication modes:*

Value files support different communication modes for security:

Plain mode (no encryption):
```
pm3 --> hf mfdes value --aid 123456 --fid 02 --op get -m plain
[+] Value: 125 (0x0000007d)
```

MAC mode (message authentication):
```
pm3 --> hf mfdes value --aid 123456 --fid 02 --op credit -d 00000032 -m mac
[+] Value changed successfully
```

Encrypted mode (full encryption):
```
pm3 --> hf mfdes value --aid 123456 --fid 02 --op debit -d 00000014 -m encrypted
[+] Value changed successfully
```

*Error handling and compatibility:*

The Proxmark3 implementation includes automatic fallback for compatibility:
- If MAC mode fails with a length error (-20), it automatically retries in plain mode
- This ensures compatibility across different DESFire card generations
- Original communication mode is restored after fallback

*Transaction behavior:*

Value operations are atomic with automatic commit:
- The `hf mfdes value` command automatically issues CommitTransaction after credit/debit operations
- Get operations do not require a commit
- Operations either complete fully (including commit) or fail completely
- No manual transaction management required when using the `hf mfdes value` command
- Transaction MAC files can log all value operations for audit trails

*Practical examples:*

Daily Bitcoin IOU catastrophes:
```
# Check morning IOU balance
pm3 --> hf mfdes value --aid 425443 --fid 01 --op get
[+] Value: 50 (0x00000032)  # $6 million in IOUs

# Friend sends you more IOUs via NFC bump
pm3 --> hf mfdes value --aid 425443 --fid 01 --op credit -d 000000C8
[+] Value changed successfully  # +200 BTC IOUs ($24M more debt)

# Buy a Tesla (tap payment)
pm3 --> hf mfdes value --aid 425443 --fid 01 --op debit -d 00000001
[+] Value changed successfully

# Check remaining IOU capacity
pm3 --> hf mfdes value --aid 425443 --fid 01 --op get
[+] Value: 273 (0x00000111)  # $32.76M in transferable debt
```


### How to work with transaction mac
^[Top](#top)

There are two types of transactions with mac: with and without the CommitReaderID command. The type can be chosen by `hf mfdes createmacfile` command.

By default, the application works with transactions. All the write operations except write to standard file need to be committed by CommitTransaction command.

CommitTransaction command issued at the end of each write operation (except standard file).

Mac mode of transactions can be switched on by creating a mac file. There may be only one file with this file type for one application.

Command CommitReaderID enable/disable mode can be chosen at the creation of this file.

When CommitReaderID is enabled, it is needed to issue this command once per transaction. The transaction can't be committed without this command.

When the command is disabled - CommitReaderID returns an error.

*more info from MF2DL(H)x0 datasheet (link at the top of this document):*

10.3.2.1 Transaction MAC Counter (page 41)

10.3.2.5 Transaction MAC Reader ID and its encryption (page 43)

10.3.3 Transaction MAC Enabling (page 44)

10.3.4 Transaction MAC Calculation (page 45)

10.3.4.3 CommitReaderID Command (page 47)

*create mac file:*

`hf mfdes createmacfile --aid 123456 --fid 0f --rawrights 0FF0 --mackey 00112233445566778899aabbccddeeff --mackeyver 01` - create transaction mac file. CommitReaderID disabled

`hf mfdes createmacfile --aid 123456 --fid 0f --rawrights 0F10 --mackey 00112233445566778899aabbccddeeff --mackeyver 01` - create transaction mac file. CommitReaderID enabled with key 1

*read mac and transactions counter from mac file:*

`hf mfdes read --aid 123456 --fid 0f` - with type autodetect

*write to data file without CommitReaderID:*

`hf mfdes write --aid 123456 --fid 01 -d 01020304`

*write to data file with CommitReaderID:*

`hf mfdes write --aid 123456 --fid 01 -d 01020304 --readerid 010203`

*write to data file with CommitReaderID and decode previous reader ID:*

**Note about CommitReaderID in MAC mode:** If CommitReaderID fails with permission or length errors in MAC mode, the command will automatically retry in plain mode for better compatibility with different card configurations. This auto-fallback mechanism ensures reliable operation across various DESFire implementations.

step 1. read mac file or read all the files to get transaction mac counter

`hf mfdes read --aid 123456 --fid 0f` - read mac file

`hf mfdes dump --aid 123456` - read all the files

step 2. write something to a file with CommitReaderID command and provide the key that was set by `hf mfdes createmacfile` command

`hf mfdes write --aid 123456 --fid 01 -d 01020304 --readerid 010203 --trkey 00112233445566778899aabbccddeeff`

#### Enhanced Transaction MAC Commands (EV2/EV3)

The following commands provide enhanced Transaction MAC workflow support with improved security and validation:

*validate TMAC context and configuration:*

`hf mfdes validatetmac --aid 123456` - validate Transaction MAC context for application 123456

`hf mfdes validatetmac --aid 123456 --schann ev2` - validate using EV2 secure channel

*get TMAC counter and value directly:*

`hf mfdes gettmac --aid 123456 --fid 01` - get TMAC counter and value from file 01

`hf mfdes gettmac --aid 123456 --fid 01 --schann lrp` - get TMAC using LRP secure channel

*execute CommitReaderID with secure encryption:*

`hf mfdes commitreaderid --aid 123456 --rid 1122334455667788` - commit reader ID with secure encryption

`hf mfdes commitreaderid --aid 123456 --rid 1122334455667788 --schann ev2` - commit using EV2 channel

#### Enhanced Features in EV2/EV3 Mode

When working with EV2/EV3 cards, the following enhancements are automatically enabled:

- **Transaction Identifier (TI) Validation**: Automatic validation of TI consistency during sessions
- **Enhanced IV Generation**: TI-based IV generation with TMAC counter integration for improved security
- **Enhanced CMAC Calculation**: TMAC-aware CMAC calculation with enhanced counter handling
- **Automatic TMAC Context Management**: Context automatically updated when switching applications

These enhancements provide better security and are compatible with all existing DESFire commands.

#### Transaction MAC File Format and Analysis

Transaction MAC files (file type 0x05) store transaction security information with the following 12-byte structure:

**File Structure:**
```
Offset 0-3:  Transaction Counter (4 bytes, little-endian)
Offset 4-11: Transaction MAC Value (8 bytes)
```

**Analyzing TMAC Files:**

*comprehensive TMAC file analysis with human-readable output:*

`hf mfdes analyzetmac --aid 123456 --fid 01` - analyze TMAC file structure, counter status, and access rights

`hf mfdes analyzetmac --aid 123456 --fid 01 -v` - verbose analysis with detailed file settings and counter interpretation

`hf mfdes analyzetmac --aid 123456 --fid 01 --txlog -v` - complete transaction context with analysis

**Analysis Output Includes:**
- Transaction counter value and status (initialized, active, maximum)
- Transaction MAC value and validation
- Access rights interpretation (CommitReaderID requirements)
- File settings and security configuration
- LRP channel support with split counter handling
- Context validation against current session state

**Counter States:**
- `0x00000000`: Initialized (never used)
- `0x00000001-0xFFFFFFFE`: Active (number indicates transaction count)
- `0xFFFFFFFF`: Maximum reached (requires attention)

**Access Rights for CommitReaderID:**
- `rwAccess = 0x0F`: CommitReaderID disabled
- `rwAccess = 0x0E`: CommitReaderID free access (no authentication)
- `rwAccess = 0x0-0x4`: CommitReaderID requires authentication with specified key

#### EV2/EV3 Card Compatibility

**Full Backward Compatibility:** EV3 cards work seamlessly with EV2 implementations. The key differences:

- **EV2 Cards**: Support Transaction MAC files with basic functionality
- **EV3 Cards**: Enhanced Transaction MAC with improved security features
- **Implementation**: Both use the same `EV2` secure channel (`--schann ev2`)

**Testing EV2 Features on EV3 Cards:**

All EV2 commands work identically on EV3 cards:

`hf mfdes auth --aid 123456 --schann ev2` - EV2 authentication works on both EV2 and EV3

`hf mfdes commitreaderid --aid 123456 --rid 1122334455667788 --schann ev2` - CommitReaderID identical on both

`hf mfdes validatetmac --aid 123456 --schann ev2` - TMAC validation works for both card types

**Enhanced Features Available on Both:**
- Transaction Identifier (TI) validation
- Enhanced IV generation with TMAC counter integration  
- Enhanced CMAC calculation with transaction context
- Automatic TMAC context management
- CommitReaderID with encrypted previous ReaderID (EncTMRI)

**Version Detection:**
```
EV2: Type=0x01, Major=0x22, Minor=0x00
EV3: Type=0x01, Major=0x33, Minor=0x00
```

Both versions receive identical security treatment through the unified EV2 secure channel implementation.

**EV2/EV3 Protocol Enhancements:**

The EV2/EV3 secure channel provides several critical improvements over EV1:

- **Enhanced Transaction Identifier (ETI)**: Integrates TMAC counter with TI for improved replay protection
- **DACEV2 Channel**: Unified secure channel implementation for both EV2 and EV3 card types
- **Encrypted TMRI (EncTMRI)**: Previous ReaderID encrypted in CommitReaderID responses for enhanced security
- **Enhanced CMAC**: Transaction-aware CMAC calculation with improved key derivation
- **Automatic Context Management**: Session state automatically maintained across application switches

**Practical Testing Examples:**

*verify card version and compatibility:*
```
pm3 --> hf mfdes info
[+] Card Type         : MIFARE DESFire EV3 8k
[+] Version           : Type=0x01, Major=0x33, Minor=0x00
[+] Secure Channel    : EV2 (compatible)
```

*test EV2 features on EV3 card:*
```
pm3 --> hf mfdes auth --aid 123456 --schann ev2 -t aes
[+] Authentication ( AES ) success.

pm3 --> hf mfdes commitreaderid --aid 123456 --rid 1122334455667788
[+] CommitReaderID ( 1122334455667788 ) success.
[+] EncTMRI: 99AABBCCDDEEFF00
```

### How to switch DESFire Light to LRP mode
^[Top](#top)

Remove failed authentication counters (if needs, but strongly recommended)

`hf mfdes setconfig --appisoid df01 -t aes -s ev2 --param 0a --data 00ffffffff`

or in the LRP mode

`hf mfdes setconfig --appisoid df01 -t aes -s lrp --param 0a --data 00ffffffff`

Switch LRP mode on

`hf mfdes setconfig --appisoid df01 -t aes -s ev2 --param 05 --data 00000000010000000000`


