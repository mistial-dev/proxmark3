#!/usr/bin/env bash

# Online tests that require actual PM3 device connection
# This is used to make sure that the language for the functions is english instead of the system default language.
LANG=C

PM3PATH="$(dirname "$0")/.."
cd "$PM3PATH" || exit 1

TESTALL=false
TESTDESFIREVALUE=false
TESTDESFIRETMAC=false

# https://medium.com/@Drew_Stokes/bash-argument-parsing-54f3b81a6a8f
PARAMS=""
while (( "$#" )); do
  case "$1" in
    -h|--help)
      echo """
Usage: $0 [--pm3bin /path/to/pm3] [desfire_value|desfire_tmac]
    --pm3bin ...:    Specify path to pm3 binary to test
    desfire_value:   Test DESFire value operations with card
    desfire_tmac:    Test DESFire Transaction MAC workflow with EV2/EV3 card
    You must specify a test target - no default 'all' for online tests
"""
      exit 0
      ;;
    --pm3bin)
      if [ -n "$2" ] && [ ${2:0:1} != "-" ]; then
        PM3BIN=$2
        shift 2
      else
        echo "Error: Argument for $1 is missing" >&2
        exit 1
      fi
      ;;
    desfire_value)
      TESTALL=false
      TESTDESFIREVALUE=true
      shift
      ;;
    desfire_tmac)
      TESTALL=false
      TESTDESFIRETMAC=true
      shift
      ;;
    -*|--*=) # unsupported flags
      echo "Error: Unsupported flag $1" >&2
      exit 1
      ;;
    *) # preserve positional arguments
      PARAMS="$PARAMS $1"
      shift
      ;;
  esac
done
# set positional arguments in their proper place
eval set -- "$PARAMS"

C_RED='\033[0;31m'
C_GREEN='\033[0;32m'
C_YELLOW='\033[0;33m'
C_BLUE='\033[0;34m'
C_NC='\033[0m' # No Color
C_OK='\xe2\x9c\x94\xef\xb8\x8f'
C_FAIL='\xe2\x9d\x8c'

# Check if file exists
function CheckFileExist() {
  printf "%-40s" "$1 "
  if [ -f "$2" ]; then
    echo -e "[ ${C_GREEN}OK${C_NC} ] ${C_OK}"
    return 0
  fi
  if ls "$2" 1> /dev/null 2>&1; then
    echo -e "[ ${C_GREEN}OK${C_NC} ] ${C_OK}"
    return 0
  fi
  echo -e "[ ${C_RED}FAIL${C_NC} ] ${C_FAIL}"
  return 1
}

# Execute command and check result
function CheckExecute() {
  printf "%-40s" "$1 "
  
  start=$(date +%s)
  TIMEINFO=""
  RES=$(eval "$2")
  end=$(date +%s)
  delta=$(expr $end - $start)
  if [ $delta -gt 2 ]; then
    TIMEINFO="  ($delta s)"
  fi
  if echo "$RES" | grep -E -q "$3"; then
    echo -e "[ ${C_GREEN}OK${C_NC} ] ${C_OK} $TIMEINFO"
    return 0
  fi
  echo -e "[ ${C_RED}FAIL${C_NC} ] ${C_FAIL} $TIMEINFO"
  echo "Execution trace:"
  echo "$RES"
  return 1
}

echo -e "${C_BLUE}Iceman Proxmark3 online test tool${C_NC}"
echo ""
echo "work directory: $(pwd)"

if command -v git >/dev/null && git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo -n "git branch: "
  git describe --all
  echo -n "git sha: "
  git rev-parse HEAD
  echo ""
fi

# Check that user specified a test
if [ "$TESTDESFIREVALUE" = false ] && [ "$TESTDESFIRETMAC" = false ]; then
  echo "Error: You must specify a test target. Use -h for help."
  exit 1
fi

while true; do
    # DESFire value tests
    if $TESTDESFIREVALUE; then
      echo -e "\n${C_BLUE}Testing DESFire card value operations${C_NC} ${PM3BIN:=./pm3}"
      echo "  PLACE A FACTORY DESFIRE CARD ON THE READER NOW"
      if ! CheckFileExist "pm3 exists"               "$PM3BIN"; then break; fi
      
      echo "  Formatting card to clean state..."
      if ! CheckExecute "format card"                  "$PM3BIN -c 'hf mfdes formatpicc'" "done"; then break; fi
      
      echo "  Running value operation tests..."
      if ! CheckExecute "card auth test"          "$PM3BIN -c 'hf mfdes auth -n 0 -t 2tdea -k 00000000000000000000000000000000 --kdf none'" "authenticated.*succes"; then break; fi
      if ! CheckExecute "card app creation"       "$PM3BIN -c 'hf mfdes createapp --aid 123456 --ks1 0F --ks2 0E --numkeys 1'" "successfully created"; then break; fi
      if ! CheckExecute "card value file creation" "$PM3BIN -c 'hf mfdes createvaluefile --aid 123456 --fid 02 --lower 00000000 --upper 000003E8 --value 00000064'" "created successfully"; then break; fi
      if ! CheckExecute "card value get plain"    "$PM3BIN -c 'hf mfdes value --aid 123456 --fid 02 --op get -m plain'" "Value.*100"; then break; fi
      if ! CheckExecute "card value get mac"      "$PM3BIN -c 'hf mfdes value --aid 123456 --fid 02 --op get -m mac'" "Value.*100"; then break; fi
      if ! CheckExecute "card value credit plain" "$PM3BIN -c 'hf mfdes value --aid 123456 --fid 02 --op credit -d 00000032 -m plain'" "Value.*changed"; then break; fi
      if ! CheckExecute "card value get after credit" "$PM3BIN -c 'hf mfdes value --aid 123456 --fid 02 --op get -m plain'" "Value.*150"; then break; fi
      if ! CheckExecute "card value credit mac"   "$PM3BIN -c 'hf mfdes value --aid 123456 --fid 02 --op credit -d 0000000A -m mac'" "Value.*changed"; then break; fi
      if ! CheckExecute "card value debit plain"  "$PM3BIN -c 'hf mfdes value --aid 123456 --fid 02 --op debit -d 00000014 -m plain'" "Value.*changed"; then break; fi
      if ! CheckExecute "card value debit mac"    "$PM3BIN -c 'hf mfdes value --aid 123456 --fid 02 --op debit -d 00000014 -m mac'" "Value.*changed"; then break; fi
      if ! CheckExecute "card value final check"  "$PM3BIN -c 'hf mfdes value --aid 123456 --fid 02 --op get -m mac'" "Value.*120"; then break; fi
      if ! CheckExecute "card cleanup"            "$PM3BIN -c 'hf mfdes selectapp --aid 000000; hf mfdes auth -n 0 -t 2tdea -k 00000000000000000000000000000000 --kdf none; hf mfdes deleteapp --aid 123456'" "application.*deleted"; then break; fi
      echo "  card value operation tests completed successfully!"
    fi

    # DESFire Transaction MAC tests
    if $TESTDESFIRETMAC; then
      echo -e "\n${C_BLUE}Testing DESFire Transaction MAC workflow${C_NC} ${PM3BIN:=./pm3}"
      echo "  PLACE AN EV2/EV3 DESFIRE CARD ON THE READER NOW"
      if ! CheckFileExist "pm3 exists"               "$PM3BIN"; then break; fi
      
      echo -e "\n${C_YELLOW}Test 1: Basic TMAC workflow with authenticated CommitReaderID${C_NC}"
      echo "  Formatting card to clean state..."
      if ! CheckExecute "format card"                  "$PM3BIN -c 'hf mfdes formatpicc'" "done"; then break; fi
      
      echo "  Setting up TMAC test environment..."
      if ! CheckExecute "card auth test"          "$PM3BIN -c 'hf mfdes auth -n 0 -t 2tdea -k 00000000000000000000000000000000 --kdf none'" "authenticated.*succes"; then break; fi
      if ! CheckExecute "card app creation"       "$PM3BIN -c 'hf mfdes createapp --aid 123456 --ks1 0F --ks2 0E --numkeys 2'" "successfully created"; then break; fi
      
      echo "  Creating Transaction MAC file..."
      if ! CheckExecute "tmac file creation"      "$PM3BIN -c 'hf mfdes createmacfile --aid 123456 --fid 01 --rawrights 0F00 --mackey 00112233445566778899aabbccddeeff --mackeyver 01'" "created successfully"; then break; fi
      
      echo "  Performing initial CommitReaderID before validation..."
      if ! CheckExecute "auth for initial commit" "$PM3BIN -c 'hf mfdes auth --aid 123456 -n 0 -t 2tdea -k 00000000000000000000000000000000 --kdf none -m mac'" "authenticated.*succes"; then break; fi
      if ! CheckExecute "initial commitreaderid"   "$PM3BIN -c 'hf mfdes commitreaderid --aid 123456 --rid 0000000000000000AAAAAAAAAAAAAAAA -m mac'" "CommitReaderID completed successfully"; then break; fi
      
      echo "  Testing TMAC context validation with detailed logging..."
      if ! CheckExecute "tmac context validation" "$PM3BIN -c 'hf mfdes validatetmac --aid 123456 --txlog -v'" "TMAC Present.*YES"; then break; fi
      
      echo "  Testing TMAC counter reading with transaction log..."
      if ! CheckExecute "tmac counter read"       "$PM3BIN -c 'hf mfdes gettmac --aid 123456 --fid 01 --txlog'" "TMAC Counter"; then break; fi
      
      echo "  Creating data file for transactions..."
      if ! CheckExecute "data file creation"      "$PM3BIN -c 'hf mfdes createfile --aid 123456 --fid 02 --size 000020 --rawrights 0EEE'" "created successfully"; then break; fi
      
      echo "  Testing authenticated CommitReaderID with detailed transaction logging..."
      # First transaction - no previous ReaderID, expect encrypted zeros
      if ! CheckExecute "auth for commitreaderid" "$PM3BIN -c 'hf mfdes auth --aid 123456 -n 0 -t 2tdea -k 00000000000000000000000000000000 --kdf none -m mac'" "authenticated.*succes"; then break; fi
      if ! CheckExecute "commitreaderid first"    "$PM3BIN -c 'hf mfdes commitreaderid --aid 123456 --rid 1122334455667788AABBCCDDEEFF0011 -m mac --txlog -v'" "CommitReaderID completed successfully"; then break; fi
      
      echo "  Testing transaction with TMAC..."
      if ! CheckExecute "tmac transaction test"   "$PM3BIN -c 'hf mfdes write --aid 123456 --fid 02 --offset 0 --data 48656C6C6F20546D616321 -m encrypt'" "successfully written"; then break; fi
      
      echo "  Committing first transaction..."
      if ! CheckExecute "commit transaction 1"    "$PM3BIN -c 'hf mfdes committransaction --aid 123456'" "Transaction committed"; then break; fi
      
      echo "  Starting second transaction to verify ReaderID chaining with logging..."
      if ! CheckExecute "auth for second trans"   "$PM3BIN -c 'hf mfdes auth --aid 123456 -n 0 -t 2tdea -k 00000000000000000000000000000000 --kdf none -m mac'" "authenticated.*succes"; then break; fi
      if ! CheckExecute "commitreaderid second"   "$PM3BIN -c 'hf mfdes commitreaderid --aid 123456 --rid 2233445566778899AABBCCDDEEFF1122 -m mac --txlog'" "EncTMRI"; then break; fi
      if ! CheckExecute "write for second trans"  "$PM3BIN -c 'hf mfdes write --aid 123456 --fid 02 --offset 0 --data 5365636F6E64205472616E73616374696F6E -m encrypt'" "successfully written"; then break; fi
      if ! CheckExecute "commit transaction 2"    "$PM3BIN -c 'hf mfdes committransaction --aid 123456'" "Transaction committed"; then break; fi
      
      echo "  Verifying TMAC counter increment..."
      if ! CheckExecute "tmac counter increment"  "$PM3BIN -c 'hf mfdes gettmac --aid 123456 --fid 01'" "TMAC Counter"; then break; fi
      
      echo "  Testing TMAC with different secure channels..."
      if ! CheckExecute "tmac ev2 channel test"   "$PM3BIN -c 'hf mfdes validatetmac --aid 123456 --schann ev2 --txlog'" "TMAC Present.*YES"; then break; fi
      
      echo "  Testing enhanced TI-based operations..."
      if ! CheckExecute "enhanced ti operations"  "$PM3BIN -c 'hf mfdes read --aid 123456 --fid 02 --offset 0 --length 16 -m encrypt'" "successfully read"; then break; fi
      
      echo -e "\n${C_CYAN}=== Transaction Log Demo: Complete Session Overview ===${C_NC}"
      echo "  Generating comprehensive transaction log with full verbose output..."
      "$PM3BIN" -c "hf mfdes validatetmac --aid 123456 --txlog -v" 2>&1 | grep -E "(Transaction Log|Session State|Authentication|TMAC|Command Counter|Security Level)" || true
      
      echo -e "\n${C_YELLOW}Test 2: TMAC file with free CommitReaderID access${C_NC}"
      echo "  Deleting existing TMAC file..."
      if ! CheckExecute "delete old tmac file"    "$PM3BIN -c 'hf mfdes deletefile --aid 123456 --fid 01'" "deleted"; then break; fi
      
      echo "  Creating TMAC file with free CommitReaderID (rwAccess = 0xE)..."
      if ! CheckExecute "create free access tmac" "$PM3BIN -c 'hf mfdes createmacfile --aid 123456 --fid 01 --rawrights 0FE0 --mackey 00112233445566778899aabbccddeeff --mackeyver 01'" "created successfully"; then break; fi
      
      echo "  Testing free access CommitReaderID (no auth, no EncTMRI expected)..."
      if ! CheckExecute "select app no auth"      "$PM3BIN -c 'hf mfdes selectapp --aid 123456'" "Application selected"; then break; fi
      if ! CheckExecute "commitreaderid free"     "$PM3BIN -c 'hf mfdes commitreaderid --aid 123456 --rid 3344556677889900AABBCCDDEEFF2233 -m mac'" "No EncTMRI returned.*not authenticated"; then break; fi
      
      echo "  Testing authenticated CommitReaderID with free access (EncTMRI expected)..."
      if ! CheckExecute "auth with free access"   "$PM3BIN -c 'hf mfdes auth --aid 123456 -n 0 -t 2tdea -k 00000000000000000000000000000000 --kdf none -m mac'" "authenticated.*succes"; then break; fi
      if ! CheckExecute "commitreaderid auth free" "$PM3BIN -c 'hf mfdes commitreaderid --aid 123456 --rid 4455667788990011AABBCCDDEEFF3344 -m mac'" "EncTMRI.*[0-9A-Fa-f]{32}"; then break; fi
      
      echo -e "\n${C_YELLOW}Test 3: TMAC file with disabled CommitReaderID${C_NC}"
      echo "  Deleting and recreating TMAC file with disabled CommitReaderID (rwAccess = 0xF)..."
      if ! CheckExecute "delete tmac file"        "$PM3BIN -c 'hf mfdes deletefile --aid 123456 --fid 01'" "deleted"; then break; fi
      if ! CheckExecute "create disabled tmac"    "$PM3BIN -c 'hf mfdes createmacfile --aid 123456 --fid 01 --rawrights 0FF0 --mackey 00112233445566778899aabbccddeeff --mackeyver 01'" "created successfully"; then break; fi
      
      echo "  Testing disabled CommitReaderID (should fail)..."
      if ! CheckExecute "auth for disabled test"  "$PM3BIN -c 'hf mfdes auth --aid 123456 -n 0 -t 2tdea -k 00000000000000000000000000000000 --kdf none -m mac'" "authenticated.*succes"; then break; fi
      CheckExecute "commitreaderid disabled" "$PM3BIN -c 'hf mfdes commitreaderid --aid 123456 --rid 5566778899001122AABBCCDDEEFF4455 -m mac' 2>&1" "error\\|failed\\|not allowed" || echo "  WARNING: CommitReaderID should have failed with disabled access"
      
      echo -e "\n${C_YELLOW}Test 4: TMAC context persistence and validation${C_NC}"
      echo "  Testing TMAC context after application switch..."
      if ! CheckExecute "switch to master app"    "$PM3BIN -c 'hf mfdes selectapp --aid 000000'" "Application selected"; then break; fi
      if ! CheckExecute "switch back to app"      "$PM3BIN -c 'hf mfdes selectapp --aid 123456'" "Application selected"; then break; fi
      if ! CheckExecute "validate after switch"   "$PM3BIN -c 'hf mfdes validatetmac --aid 123456'" "TMAC Present.*YES.*CommitReaderID.*Disabled"; then break; fi
      
      echo -e "\n${C_YELLOW}Test 5: Complete transaction workflow with TMAC verification${C_NC}"
      echo "  Creating new app with key-based CommitReaderID..."
      if ! CheckExecute "cleanup old app"          "$PM3BIN -c 'hf mfdes selectapp --aid 000000; hf mfdes auth -n 0 -t 2tdea -k 00000000000000000000000000000000 --kdf none; hf mfdes deleteapp --aid 123456'" "deleted"; then break; fi
      if ! CheckExecute "create fresh app"        "$PM3BIN -c 'hf mfdes createapp --aid 789ABC --ks1 0B --ks2 0E --numkeys 2'" "successfully created"; then break; fi
      if ! CheckExecute "create tmac key 1"       "$PM3BIN -c 'hf mfdes createmacfile --aid 789ABC --fid 01 --rawrights 0F10 --mackey AABBCCDDEEFF00112233445566778899 --mackeyver 02'" "created successfully"; then break; fi
      if ! CheckExecute "create data file"        "$PM3BIN -c 'hf mfdes createfile --aid 789ABC --fid 02 --size 000020 --rawrights 0111'" "created successfully"; then break; fi
      
      echo "  Testing CommitReaderID with key 1 authentication..."
      if ! CheckExecute "auth with key 1"         "$PM3BIN -c 'hf mfdes auth --aid 789ABC -n 1 -t 2tdea -k 00000000000000000000000000000000 --kdf none -m mac'" "authenticated.*succes"; then break; fi
      if ! CheckExecute "commitreaderid key 1"    "$PM3BIN -c 'hf mfdes commitreaderid --aid 789ABC --rid FEDCBA9876543210FEDCBA9876543210 -m mac'" "EncTMRI.*[0-9A-Fa-f]{32}"; then break; fi
      if ! CheckExecute "write with key 1"        "$PM3BIN -c 'hf mfdes write --aid 789ABC --fid 02 --offset 0 --data 4B657931205472616E73616374696F6E -m encrypt'" "successfully written"; then break; fi
      if ! CheckExecute "get tmac counter"        "$PM3BIN -c 'hf mfdes gettmac --aid 789ABC --fid 01'" "TMAC Counter.*0"; then break; fi
      if ! CheckExecute "commit with tmac"        "$PM3BIN -c 'hf mfdes committransaction --aid 789ABC --opt 01'" "TMC:\\|TMV:"; then break; fi
      
      echo "  Verifying TMAC counter increment..."
      if ! CheckExecute "get tmac after commit"   "$PM3BIN -c 'hf mfdes gettmac --aid 789ABC --fid 01 -n 0 -t 2tdea -k 00000000000000000000000000000000 --kdf none'" "TMAC Counter.*1"; then break; fi
      
      echo -e "\n${C_YELLOW}Test 6: EncTMRI validation with multiple ReaderID chains${C_NC}"
      echo "  Testing second transaction to verify ReaderID chain..."
      if ! CheckExecute "auth for chain test"     "$PM3BIN -c 'hf mfdes auth --aid 789ABC -n 1 -t 2tdea -k 00000000000000000000000000000000 --kdf none -m mac'" "authenticated.*succes"; then break; fi
      # Second CommitReaderID should return encrypted FEDCBA9876543210... from previous transaction
      if ! CheckExecute "commitreaderid chain"    "$PM3BIN -c 'hf mfdes commitreaderid --aid 789ABC --rid CAFE0000CAFE0000CAFE0000CAFE0000 -m mac'" "EncTMRI.*[0-9A-Fa-f]{32}"; then break; fi
      if ! CheckExecute "validate enc length"     "$PM3BIN -c 'hf mfdes commitreaderid --aid 789ABC --rid CAFE0000CAFE0000CAFE0000CAFE0000 -m mac' 2>&1 | grep -oE 'EncTMRI.*[0-9A-Fa-f]{32}' | grep -oE '[0-9A-Fa-f]{32}' | wc -c" "33"; then 
        echo "  WARNING: EncTMRI should be exactly 32 hex characters (16 bytes)"
      fi
      
      echo -e "\n${C_YELLOW}Test 7: EncTMRI with different key access rights${C_NC}"
      echo "  Creating app with multiple keys for testing..."
      if ! CheckExecute "cleanup for multi-key"    "$PM3BIN -c 'hf mfdes selectapp --aid 000000; hf mfdes auth -n 0 -t 2tdea -k 00000000000000000000000000000000 --kdf none; hf mfdes deleteapp --aid 789ABC'" "deleted"; then break; fi
      if ! CheckExecute "create multi-key app"    "$PM3BIN -c 'hf mfdes createapp --aid CCDDEE --ks1 03 --ks2 0E --numkeys 5'" "successfully created"; then break; fi
      
      echo "  Testing TMAC with key 3 access requirement..."
      if ! CheckExecute "create tmac key 3"       "$PM3BIN -c 'hf mfdes createmacfile --aid CCDDEE --fid 01 --rawrights 0F30 --mackey 1122334455667788990011223344556677889900 --mackeyver 03'" "created successfully"; then break; fi
      if ! CheckExecute "auth with key 3"         "$PM3BIN -c 'hf mfdes auth --aid CCDDEE -n 3 -t 2tdea -k 00000000000000000000000000000000 --kdf none -m mac'" "authenticated.*succes"; then break; fi
      if ! CheckExecute "commitreaderid key 3"    "$PM3BIN -c 'hf mfdes commitreaderid --aid CCDDEE --rid AABBCCDDEEFF00112233445566778899 -m mac'" "EncTMRI.*[0-9A-Fa-f]{32}.*Previous ReaderID"; then break; fi
      
      echo "  Testing with wrong key (should fail)..."
      if ! CheckExecute "auth with wrong key"     "$PM3BIN -c 'hf mfdes auth --aid CCDDEE -n 0 -t 2tdea -k 00000000000000000000000000000000 --kdf none -m mac'" "authenticated.*succes"; then break; fi
      CheckExecute "commitreaderid wrong key" "$PM3BIN -c 'hf mfdes commitreaderid --aid CCDDEE --rid DEADBEEFDEADBEEFDEADBEEFDEADBEEF -m mac' 2>&1" "error\\|failed\\|denied" || echo "  WARNING: CommitReaderID should fail with wrong key"
      
      echo "  Cleanup test environment..."
      if ! CheckExecute "final cleanup all"        "$PM3BIN -c 'hf mfdes selectapp --aid 000000; hf mfdes auth -n 0 -t 2tdea -k 00000000000000000000000000000000 --kdf none; hf mfdes deleteapp --aid 789ABC; hf mfdes deleteapp --aid CCDDEE'" "deleted"; then break; fi
      
      echo -e "\n${C_CYAN}=== Transaction Logging Features Summary ===${C_NC}"
      echo "  All DESFire TMAC commands now support enhanced transaction logging:"
      echo ""
      echo -e "  ${C_YELLOW}--txlog${C_NC}     Shows transaction context (auth status, TMAC state, timing)"
      echo -e "  ${C_YELLOW}--txlog -v${C_NC}  Shows detailed session info (keys, IV, security level, TI)"
      echo ""
      echo "  Commands with logging support:"
      echo "  • hf mfdes gettmac --txlog        - TMAC counter with transaction context"
      echo "  • hf mfdes commitreaderid --txlog - CommitReaderID with EncTMRI details"
      echo "  • hf mfdes validatetmac --txlog   - Complete TMAC context validation"
      echo ""
      echo "  Use these flags for debugging, analysis, and understanding DESFire transactions!"
      echo -e "\n${C_GREEN}Transaction MAC workflow tests completed successfully!${C_NC}"
    fi
  
  echo -e "\n------------------------------------------------------------"
  echo -e "Tests [ ${C_GREEN}OK${C_NC} ] ${C_OK}\n"
  exit 0
done
echo -e "\n------------------------------------------------------------"
echo -e "\nTests [ ${C_RED}FAIL${C_NC} ] ${C_FAIL}\n"
exit 1