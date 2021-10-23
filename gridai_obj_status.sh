# determine status of previous grid run command
# run
# ./gridai_obj_status.sh -i 1 run daring-perch-330
# ./gridai_obj_status.sh -i 1 run rigorous-benz-3635 
# ./gridai_obj_status.sh -i 1 run inescapable-coati-929
# ./gridai_obj_status.sh -i 1 run fat-bullfinch-668
# ./gridai_obj_status.sh -i 1 run bold-shockley-7806
# ./gridai_obj_status.sh -i 1 run able-guan-94 
# session
#  ./gridai_obj_status.sh -i 1 session fluffy-rubin-4046 #  pending -- wait and time out
#  ./gridai_obj_status.sh -i 1 session g4dn-xlarge-1

# datastore

# ./gridai_obj_status.sh -i 1 datastore dali-mnist
# ./gridai_obj_status.sh -i 1 datastore dali

# cluster
#  ./gridai_obj_status.sh -i 1 cluster us-east-1-211022-220523
#  ./gridai_obj_status.sh -i 1 cluster c211020-020559
usage() { 
  cat <<EOF
$0 [options] [run|session|cluster|datastore] id
EOF
}
DEBUG() { if [ ! -z "$VERBOSE" ]; then echo "$@" 1>&2; fi;}

# defaults and matching counters
MAX_POL_CNT=10  # max number of times to poll regardless of situtations
CMD_POL_CNT=0   

MAX_ERR_CNT=2   # cmd failed
CMD_ERR_CNT=0

MAX_NOID_CNT=2  # cmd successful but id NOT found   
CMD_NOID_CNT=0

MAX_NONE_CNT=0  # cmd successful and id found and NONE of the status matched 
CMD_NONE_CNT=0

MAX_SOME_CNT=0  # cmd successful and id found and SOME status matched
CMD_SOME_CNT=0

# 
POLL_SEC_INTERVAL=60
SOME_THRESHOLD_PERCENT=100  # TODO
TARGET_STATE=
VERBOSE=

# grid cli truncates names and status when col is too small
MAX_TERM_COLS=512 # used to set stty cols $MAX_TERM_COLS

# command line args
while getopts "p:e:n:z:s:t:i:v" arg; do
  case $arg in
    p)
      MAX_POL_CNT=$OPTARG 
      ;;
    e)
      MAX_ERR_CNT=$OPTARG 
      ;;
    n)
      MAX_NOID_CNT=$OPTARG 
      ;;
    z)
      MAX_NONE_CNT=$OPTARG 
      ;;    
    s)
      MAX_SOME_CNT=$OPTARG 
      ;; 
    t)  
      TARGET_STATE=$OPTARG   
      ;;
    i)
      POLL_SEC_INTERVAL=$OPTARG 
      ;;
    v)
      VERBOSE=1 
      ;;      
    *)
      usage
      ;;      
  esac
done
shift $((OPTIND-1))

# required args and syntax
if [[ $# -ne 2 ]]; then usage; exit; fi
OBJ_TYPE=$1
OBJ_ID=$2
case $OBJ_TYPE in
  run)        
    TARGET_STATE="succeeded|cancelled|failed|stopped"
    OBJ_ID_COL=2 
    OBJ_STATUS_COL=4 
    ;;
  session)    
    TARGET_STATE="failed|stopped|paused" 
    OBJ_ID_COL=2 
    OBJ_STATUS_COL=3
    OBJ_DURATION_COL=5
    ;;
  datastore)  
    TARGET_STATE="Succeeded" 
    OBJ_ID_COL=3 
    OBJ_STATUS_COL=8
    OBJ_DURATION_COL=6
    ;;
  cluster)    
    TARGET_STATE="running" 
    OBJ_ID_COL=2 
    OBJ_STATUS_COL=5
    OBJ_DURATION_COL=6
    ;;
  *)          
    usage 
    exit 1 
    ;;
esac

# increase stty column so that long names are fully displayed
if [[ ! -z "$MAX_TERM_COLS" ]]; then stty cols $MAX_TERM_COLS; fi

# pool at interval
RC=1
echo "${OBJ_TYPE}:${OBJ_ID}: looking for ${SOME_THRESHOLD_PERCENT}% in ${TARGET_STATE}" 
while [ $CMD_POL_CNT -lt $MAX_POL_CNT ]; do 
  DEBUG "while $CMD_POL_CNT -lt $MAX_POL_CNT"
  # retrieve the object status  
  case $OBJ_TYPE in
    run)
      OBJ_ID_EXP="^${OBJ_ID}-exp[0-9]+$"
      grid status ${OBJ_ID} > grid.status.log 2>&1
      ;;
    session)
      OBJ_ID_EXP="^${OBJ_ID}$"
      grid session > grid.status.log 2>&1
      ;;
    datastore)
      OBJ_ID_EXP="^${OBJ_ID}$"
      grid datastore > grid.status.log 2>&1
      ;;
    cluster) 
      OBJ_ID_EXP="^${OBJ_ID}$"
      grid clusters > grid.status.log 2>&1
      ;;
    *) 
      usage 
      exit 1 
      ;;
  esac

  # save the command status and output
  GRID_CMD_STATUS=$?
  cat grid.status.log | awk -F│ '{gsub(/^[ \t]+|[ \t]+$/, "", $i); gsub(/^[ \t]+|[ \t]+$/, "", $s); if ( $i ~ o ) print $s; }' i=$OBJ_ID_COL s=$OBJ_STATUS_COL o=$OBJ_ID_EXP > grid.tally.log

  # nuber of entries in STOP
  TOTAL_ENTRIES=$((`cat grid.tally.log | wc -l`))
  TOTAL_MATCH=$((`egrep -w -e "$TARGET_STATE" grid.tally.log | wc -l`))
  OBJ_STATUS=$(cat grid.tally.log | paste -s -d, -)
  DEBUG "TOTAL_ENTRIES=$TOTAL_ENTRIES TOTAL_MATCH=$TOTAL_MATCH"

  # exit condition checks
  if [[ $GRID_CMD_STATUS != 0 ]]; then 
      DEBUG "cmd failed"
      cat grid.status.log
      (( CMD_ERR_CNT = CMD_ERR_CNT + 1 )); 
      if [[ MAX_ERR_CNT -gt 0 && CMD_ERR_CNT -ge MAX_ERR_CNT ]]; then break; fi 
  elif [[ $TOTAL_ENTRIES == 0 ]]; then
      DEBUG "id NOT found"
      cat grid.status.log
      (( CMD_NOID_CNT = CMD_NOID_CNT + 1 )); 
      if [[ MAX_NOID_CNT -gt 0 && CMD_NOID_CNT -ge MAX_NOID_CNT ]]; then break; fi   
  elif [[ $TOTAL_MATCH == 0 ]]; then
      DEBUG "NONE matched status"
      (( CMD_NONE_CNT = CMD_NONE_CNT + 1 )); 
      if [[ MAX_NONE_CNT -gt 0 && CMD_NONE_CNT -ge MAX_NONE_CNT ]]; then break; fi  
  elif [[ $TOTAL_MATCH -ne $TOTAL_ENTRIES ]]; then
      DEBUG "SOME matched status"
      (( CMD_SOME_CNT = CMD_SOME_CNT + 1 )); 
      if [[ MAX_SOME_CNT -gt 0 && CMD_SOME_CNT -ge MAX_SOME_CNT ]]; then break; fi  
  else 
    DEBUG "ALL matched status"
    RC=0
    break    
  fi

  (( CMD_POL_CNT = CMD_POL_CNT + 1 ))
  echo "${CMD_POL_CNT}:${OBJ_TYPE}:${OBJ_ID}:$(sort grid.tally.log | uniq -c - | paste -s -)" 
done

echo "${OBJ_TYPE}:${OBJ_ID}:$(sort grid.tally.log | uniq -c - | paste -s -)" 
# reset the stty back to original
stty >/dev/null 2>&1

# return the last status code
echo "::set-output name=obj_summary::$(sort grid.tally.log | uniq -c - | paste -s -)"
echo "::set-output name=obj_status::$OBJ_STATUS"
echo "::set-output name=obj_exit_code::$RC"
exit $RC