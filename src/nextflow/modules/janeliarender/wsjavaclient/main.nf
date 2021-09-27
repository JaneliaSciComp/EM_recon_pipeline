// structure copied from https://github.com/nf-core/modules/blob/master/modules/blast/blastn/main.nf

def render_java_client_container =
    'registry.int.janelia.org/saalfeldlab/render-ws-java-client:geometric_descriptor.e7781820'
def client_log = 'client.log'

// TODO: if possible, consolidate small/medium/large processes into one and parameterize label and jvm_memory

// TODO: is there a way to add a queue index to the tag? maybe just use job specific args

// TODO: wish there was some better way to block processing than the prior_step_succeeded input

// TODO: confirm tuple output is the way to go
//   see "Grouped inputs and outputs" in
//   https://carpentries-incubator.github.io/workflows-nextflow/05-processes-part2/index.html

// TODO: is publishDir approach needed for client log data?
//   see Organising outputs in
//   https://carpentries-incubator.github.io/workflows-nextflow/05-processes-part2/index.html
//   my goal is to be able to go back and look at client logs to debug problems

process RUN_SMALL_WS_JAVA_CLIENT {
    tag "${client_class}"
    label "jvm_small_single"  // TODO: is there any way to make this dynamic?
    container { "${render_java_client_container}" }

    input:
    val client_class
    val common_client_args
    val job_specific_client_args
    val prior_step_succeeded

    output:
    tuple env(ERROR_COUNT), path("${client_log}"), emit: client_result

    script:
    def jvm_memory = '1G' // TODO: this is tightly coupled to labelled process config, can it be derived?
    """
    CLIENT_ARGS="${jvm_memory} ${client_class} ${common_client_args} ${job_specific_client_args}"
    /render/render-ws-java-client/src/main/scripts/run_ws_client.sh \${CLIENT_ARGS} > ${client_log}
    ERROR_COUNT=\$(grep -ic error ${client_log} || true) # note: need || true here to ensure 0 exit code
    """
}

process RUN_MEDIUM_WS_JAVA_CLIENT {
    tag "${client_class}"
    label "jvm_medium_single"  // TODO: is there any way to make this dynamic?
    container { "${render_java_client_container}" }

    input:
    val client_class
    val common_client_args
    val job_specific_client_args
    val prior_step_succeeded

    output:
    tuple env(ERROR_COUNT), path("${client_log}"), emit: client_result

    script:
    def jvm_memory = '6G' // TODO: this is tightly coupled to labelled process config, can it be derived?
    """
    CLIENT_ARGS="${jvm_memory} ${client_class} ${common_client_args} ${job_specific_client_args}"
    /render/render-ws-java-client/src/main/scripts/run_ws_client.sh \${CLIENT_ARGS} > ${client_log}
    ERROR_COUNT=\$(grep -ic error ${client_log})
    """
}

process RUN_LARGE_WS_JAVA_CLIENT {
    tag "${client_class}"
    label "jvm_large_single"  // TODO: is there any way to make this dynamic?
    container { "${render_java_client_container}" }

    input:
    val client_class
    val common_client_args
    val job_specific_client_args
    val prior_step_succeeded

    output:
    tuple env(ERROR_COUNT), path("${client_log}"), emit: client_result

    script:
    def jvm_memory = '14G' // TODO: this is tightly coupled to labelled process config, can it be derived?
    """
    CLIENT_ARGS="${jvm_memory} ${client_class} ${common_client_args} ${job_specific_client_args}"
    /render/render-ws-java-client/src/main/scripts/run_ws_client.sh \${CLIENT_ARGS} > ${client_log}
    ERROR_COUNT=\$(grep -ic error ${client_log})
    """
}
