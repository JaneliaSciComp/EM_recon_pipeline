#!/usr/bin/env nextflow

nextflow.enable.dsl = 2

include {
  RUN_SMALL_WS_JAVA_CLIENT as RUN_FIRST_BATCH;
  RUN_SMALL_WS_JAVA_CLIENT as RUN_MIDDLE_BATCH;
  RUN_SMALL_WS_JAVA_CLIENT as RUN_LAST_BATCH;
} from '../../../modules/janeliarender/wsjavaclient/main.nf'

// TODO: should these functions be pulled out into a functions.nf file or is it ok to leave here?

def print_non_zero_error_counts(context, client_result) {
    client_result.map {
        def (error_count, client_log) = it
        if (error_count.toInteger() > 0) {
            println("$context error count: $error_count")
        }
    }
}

def print_error_count_sum(context, client_result) {
    client_result.sum {
        def (error_count, client_log) = it
        error_count.toInteger()
    }.collect().view {
        def sum = it[0]
        println("$context error count sum: $sum")
    }
}

// TODO: learn best way to document subworkflows, maybe a meta.yml file?

// TODO: add MEDIUM and LARGE jvm profile variants or find a way to parameterize this workflow

// Runs small jvm profile web services java client in 3 sequential (first, then middle, then last) batches.
// Usually the first batch contains a small number of tasks and is used to setup data and verify correctness
// before launching the middle batch which contains all remaining tasks except the last one.
// Once the middle batch completes, the last batch is launched.
// The last batch arguments usually include a data summarization flag like "--completeStack" for work that
// should only be done once everything else has finished.
workflow RUN_SMALL_WS_JAVA_CLIENT_BATCHES {
    take:
    client_class
    common_client_args
    first_batch_args
    middle_batch_args
    last_batch_args

    main:
    RUN_FIRST_BATCH(client_class, common_client_args, first_batch_args, true)
    print_non_zero_error_counts("first batch", RUN_FIRST_BATCH.out.client_result)
    print_error_count_sum("first batch", RUN_FIRST_BATCH.out.client_result)

    RUN_MIDDLE_BATCH(client_class, common_client_args, middle_batch_args, RUN_FIRST_BATCH.out.client_result)
    print_non_zero_error_counts("middle batch", RUN_MIDDLE_BATCH.out.client_result)
    print_error_count_sum("middle batch", RUN_MIDDLE_BATCH.out.client_result)

    RUN_LAST_BATCH(client_class, common_client_args, last_batch_args, RUN_MIDDLE_BATCH.out.client_result)
    print_non_zero_error_counts("last batch", RUN_LAST_BATCH.out.client_result)
    print_error_count_sum("last batch", RUN_LAST_BATCH.out.client_result)
}