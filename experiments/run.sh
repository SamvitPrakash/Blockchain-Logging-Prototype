#!/bin/bash

START="$1"
END="$2"
SEED="$3"
EXPERIMENT_NUMBER=1

./scripts/init.sh

echo
echo "========================================"
echo "Initial Run"
echo "========================================"

./scripts/generate.sh 2 1 "$SEED"

mkdir -p experiments/results/test_1
cat > "experiments/results/test_1/info.txt" <<EOF
    Number of towers [Start]: $START
    Number of towers [End]: $END
    Seed: $SEED
EOF

echo
echo "========================================"
echo "Starting logger"
echo "========================================"

./experiments/test_1/test_1.sh &
LOGGER_PID=$!

for i in $(seq $START $END); do
    echo
    echo "========================================"
    echo "Running experiment number $i with seed $SEED"
    echo "========================================"
    echo

    for (( j=1; j<=i; j++ )); do
        if (( j * 2 > i )); then
            continue
        fi

        ./experiments/test_1/run_test.sh "$i" "$j" "$SEED" "$EXPERIMENT_NUMBER"
        cp "build/fabric-network/topology.json" "experiments/results/test_1/topology_experiment_$EXPERIMENT_NUMBER.json"
        EXPERIMENT_NUMBER=$((EXPERIMENT_NUMBER + 1))
            
    done

done

kill -TERM "$LOGGER_PID"
wait "$LOGGER_PID" || true

./scripts/teardown-verbose.sh

echo
echo "========================================"
echo "All experiments completed"
echo "========================================"