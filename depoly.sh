#!/bin/bash
# author: ke.yi (aaron)

#ARGS=$(getopt -o hf: -- "$@")
#if [ $? != 0 ]; then echo "terminating ..." >&2; exit; fi
#if [ $# -lt 1 ]; then echo "use -h/--help to check available options" >&2; exit; fi

#set -- $ARGS;
#while true;
#do
#    case "$1" in
#        -f|--folder)
#	    FOLDER=$2
#	    shift 2
#	    ;;
#        -h|--help)
#            echo "script option as follows:"
#            echo -e "\t-f: assign folder path to store package"
#            shift
#            ;;
#        --)
#            shift
#            break
#            ;;
#        *)
#            echo "unknow options:{$1}"
#            exit 1
#            ;;
#    esac
#done

while getopts :f:n:p:v:h opt
do 
    case "$opt" in 
      f) echo "debug usage, f option with value $OPTARG"
	 FOLDER=$OPTARG;;
      p) echo "debug usage, p option with value $OPTARG"
	 PORT=$OPTARG;;
      n) echo "debug usage, n option with value $OPTARG"
	 NODES=$OPTARG;;
      v) echo "debug usage, v option with value $OPTARG"
	 VERSION=$OPTARG;;
      h) echo "available action as follows:"
	 echo -e "\t-f: assign folder path to store package"
	 echo -e "\t-p: assign port number to start with"
	 echo -e "\t-n: assign cluster node number"
	 echo -e "\t-v: assign redis version"
	 exit;;
      *) echo "unknown option: $opt";;
    esac
done

echo -e "\033[47;34mdownload necessary packages\033[0m"
apt-get install -y gcc g++
apt-get install -y libjemalloc-dev
apt-get install -y libhiredis-dev
apt-get install -y tcl
apt-get install -y ruby
apt-get install -y make

echo -e "\033[47;34mdownload redis and compile\033[0m"
if [ -z "$(wget http://download.redis.io/releases/redis-$VERSION.tar.gz)" ]; then
    echo 'package downloading successful'
    tar -xvf "redis-$VERSION.tar.gz"
else
    echo 'package downloading fail'
fi

if [ -z "$(tar -xzvf redis-$VERSION.tar.gz)" ]; then
    echo 'uncompress successful'
else
    echo 'uncompress failed'
fi

cd "redis"-$VERSION/deps
make lua jemalloc linenoise lua hiredis
cd ..
make && make install 
make test

echo -e "\033[47;34mconfigure per nodes\033[0m"
echo 'current path is '$(pwd)''
_NODES=$NODES
_PORT=$PORT
mkdir -p $FOLDER/cluster
while [ $_NODES -gt 0 ]
do
    mkdir -p $FOLDER/cluster/$_PORT
    #echo $($FOLDER/cluster/$_PORT/nodes-$_PORT.conf)
    cat << EOF > $FOLDER/cluster/$_PORT/nodes-$_PORT.conf
bind 127.0.0.1
port $_PORT
tcp-backlog 511
timeout 0
tcp-keepalive 300
supervised no
daemonize yes
pidfile /var/run/redis_$_PORT.pid
loglevel notice
logfile “”
databases 16
always-show-logo yes
save 900 1
save 300 10
save 60 10000
stop-writes-on-bgsave-error yes
rdbcompression yes
rdbchecksum yes
dbfilename dump.rdb
dir ./
replica-serve-stale-data yes
masterauth Beijing1
replica-read-only yes
repl-diskless-sync no
repl-diskless-sync-delay 5
repl-disable-tcp-nodelay no
replica-priority 100
lazyfree-lazy-eviction no
lazyfree-lazy-expire no
lazyfree-lazy-server-del no
replica-lazy-flush no
appendonly yes
appendfilename appendonly.aof
appendfsync everysec
no-appendfsync-on-rewrite no
auto-aof-rewrite-percentage 100
auto-aof-rewrite-min-size 64mb
aof-load-truncated yes
aof-use-rdb-preamble yes
lua-time-limit 5000

cluster-enabled yes
cluster-config-file nodes-$_PORT.conf
cluster-node-timeout 5000

slowlog-log-slower-than 10000
slowlog-max-len 128
latency-monitor-threshold 0
notify-keyspace-events "A"
hash-max-ziplist-entries 512
hash-max-ziplist-value 64
list-max-ziplist-size -2
list-compress-depth 0
set-max-intset-entries 512
zset-max-ziplist-entries 128
zset-max-ziplist-value 64
hll-sparse-max-bytes 3000
stream-node-max-bytes 4096
stream-node-max-entries 100
activerehashing yes
client-output-buffer-limit normal 0 0 0
client-output-buffer-limit replica 256mb 64mb 60
client-output-buffer-limit pubsub 32mb 8mb 60
hz 10
dynamic-hz yes
aof-rewrite-incremental-fsync yes
rdb-save-incremental-fsync yes
EOF
    MEMBER="$MEMBER 127.0.0.1:$_PORT " 
    _NODES=$[ $_NODES - 1 ]
    _PORT=$[ $_PORT + 1 ]
done
if [ $[ $(ps -ef | grep redis-server | wc -l) - 1 ] == $NODES ];
then
    echo "expected number of nodes ($NODES) running"
else
    echo "running nodes $[ $(ps -ef | grep redis-server | wc -l) - 1 ]"
    echo "configured nodes $NODES"
fi

redis-cli --cluster create $MEMBER --cluster-replicas 1 2>/dev/null

echo -e "\033[47;34mcheck redis cluster status\033[0m"
redis-cli -p $PORT cluster nodes
