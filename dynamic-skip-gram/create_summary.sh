#!/bin/bash

# target-context pair generator config
WINDOW_SIZE=8
SKIP_SIZE=16

# random walk configurations for naming conventions
METHODS=(m3)
INIT_EDGE_SIZE=0.5
STREAM_SIZE=0.001
NUM_WALKS_ARR=(5)
WALK_LENGTH_ARR=(5)
P=0.25
Q=0.25
DATASET=cora
MAX_STEPS=2
NUM_RUNS=2   # counting from zero
FREEZE_EMBEDDINGS=False

# N2V parameters
TRAIN_SPLIT=1.0             # train validation split
LEARNING_RATE=0.2
EMBEDDING_SIZE=128
VOCAB_SIZE=2708            # Size of vocabulary
NEG_SAMPLE_SIZE=5
N_EPOCHS=2                      #Starts from zero
BATCH_SIZE=200               # minibatch size
FREEZE_EMBEDDINGS=False     #If true, the embeddings will be frozen otherwise the contexts will be frozen.
DELIMITER="\\t"
FORCE_OFFSET=0                      # Offset to adjust node IDs
SEED=1234

CONFIG_SIG="ts$TRAIN_SPLIT-lr$LEARNING_RATE-es$EMBEDDING_SIZE-vs$VOCAB_SIZE-ns$NEG_SAMPLE_SIZE-ne$N_EPOCHS-bs$BATCH_SIZE-fe$FREEZE_EMBEDDINGS-s$SEED"

SUMMARY_DIR="/home/ubuntu/hooman/output/$DATASET/summary"
mkdir $SUMMARY_DIR
SUMMARY_SCORE_FILE="$SUMMARY_DIR/score-summary.csv"
SUMMARY_EPOCH_TIME="$SUMMARY_DIR/epoch-summary.csv"
SUMMARY_RW_TIME="$SUMMARY_DIR/rw-time-summary.csv"
SUMMARY_RW_WALK="$SUMMARY_DIR/rw-walk-summary.csv"
SUMMARY_RW_STEP="$SUMMARY_DIR/rw-step-summary.csv"

echo "method,nw,wl,run,step,epoch,train_acc,train_f1,test_acc,test_f1" >> $SUMMARY_SCORE_FILE

echo "method,nw,wl,run,step,epoch,time" >> $SUMMARY_EPOCH_TIME

HEADER="method\tnw\twl\trun"

for STEP in $(seq 0 $MAX_STEPS)
do
    HEADER="$HEADER\tstep$STEP"
done

echo -e "$HEADER" >> $SUMMARY_RW_TIME
echo -e "$HEADER" >> $SUMMARY_RW_WALK
echo -e "$HEADER" >> $SUMMARY_RW_STEP

trap "exit" INT

for METHOD_TYPE in ${METHODS[*]}
do
    for NUM_WALKS in ${NUM_WALKS_ARR[*]}
    do
        for WALK_LENGTH in ${WALK_LENGTH_ARR[*]}
        do
            for RUN in $(seq 0 $NUM_RUNS)
            do
                for STEP in $(seq 0 $MAX_STEPS)
                do
                    for EPOCH in $(seq 0 $N_EPOCHS)
                    do
                        printf "Run generator for method type %s\n" $METHOD_TYPE
                        printf "    Num Walks: %s\n" $NUM_WALKS
                        printf "    Walk Length: %s\n" $WALK_LENGTH
                        printf "    Run number: %s\n" $RUN
                        printf "    Step number: %s\n" $STEP
                        printf "    Epoch number: %s\n" $EPOCH

                        CONFIG=wl$WALK_LENGTH-nw$NUM_WALKS
                        SUFFIX="$METHOD_TYPE-$CONFIG-$STEP-$RUN"
                        DIR_SUFFIX="$METHOD_TYPE-is$INIT_EDGE_SIZE-$CONFIG-p$P-q$Q-ss$STREAM_SIZE"
                        DIR_PREFIX="/home/ubuntu/hooman/output"
                        SCORE_INPUT_DIR="$DIR_PREFIX/$DATASET/train/$DIR_SUFFIX/$CONFIG_SIG/s$STEP-r$RUN"
                        SCORE_FILE="$SCORE_INPUT_DIR/scores$EPOCH.txt"
                        SCORE=$(<$SCORE_FILE)
                        SUMMARY="$METHOD_TYPE,$NUM_WALKS,$WALK_LENGTH,$RUN,$STEP,$EPOCH,$SCORE"

                        EPOCH_INPUT_DIR="$DIR_PREFIX/$DATASET/emb/$DIR_SUFFIX/$CONFIG_SIG/s$STEP-r$RUN"
                        EPOCH_FILE="$EPOCH_INPUT_DIR/epoch_time.txt"

                        echo "$SUMMARY" >> $SUMMARY_SCORE_FILE

                        EPOCH_PREFIX="$METHOD_TYPE,$NUM_WALKS,$WALK_LENGTH,$RUN,$STEP"
                        while IFS='' read -r line || [[ -n "$line" ]]; do
                            echo "$EPOCH_PREFIX,$line" >> $SUMMARY_EPOCH_TIME
                        done < "$EPOCH_FILE"
                    done
                done
            done
            SUMMARY_PREFIX="$METHOD_TYPE\t$NUM_WALKS\t$WALK_LENGTH"
            STEPS_FILE="$DIR_PREFIX/$DATASET/rw/$DIR_SUFFIX/$METHOD_TYPE-steps-to-compute-wl$WALK_LENGTH-nw$NUM_WALKS.txt"
            WALK_FILE="$DIR_PREFIX/$DATASET/rw/$DIR_SUFFIX/$METHOD_TYPE-walkers-to-compute-wl$WALK_LENGTH-nw$NUM_WALKS.txt"
            TIME_FILE="$DIR_PREFIX/$DATASET/rw/$DIR_SUFFIX/$METHOD_TYPE-time-to-compute-wl$WALK_LENGTH-nw$NUM_WALKS.txt"

            counter=0
            while IFS='' read -r line || [[ -n "$line" ]]; do
                echo -e "$SUMMARY_PREFIX\t$counter\t$line" >> $SUMMARY_RW_STEP
                counter=$((counter+1))
            done < "$STEPS_FILE"
            counter=0
            while IFS='' read -r line || [[ -n "$line" ]]; do
                echo -e "$SUMMARY_PREFIX\t$counter\t$line" >> $SUMMARY_RW_WALK
                counter=$((counter+1))
            done < "$WALK_FILE"
            counter=0
            while IFS='' read -r line || [[ -n "$line" ]]; do
                echo -e "$SUMMARY_PREFIX\t$counter\t$line" >> $SUMMARY_RW_TIME
                counter=$((counter+1))
            done < "$TIME_FILE"
        done
    done
done