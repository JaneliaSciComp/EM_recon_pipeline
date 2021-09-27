#!/usr/bin/env nextflow

nextflow.enable.dsl = 2

include {
    RUN_SMALL_WS_JAVA_CLIENT_BATCHES;
} from '../../../../subworkflows/janeliarender/wsjavaclient/main.nf'


workflow TEST_RUN_SMALL_WS_JAVA_CLIENT_BATCHES {
    client_class = 'org.janelia.render.client.ValidateTilesClient'
    common_client_args = '--baseDataUrl http://renderer-dev.int.janelia.org:8080/render-ws/v1 ' +
                         '--owner flyTEM --project FAFB00 --stack v14_align_tps_20170818 ' +
                         '--validatorClass org.janelia.alignment.spec.validator.TemTileSpecValidator ' +
                         '--validatorData minCoordinate:-999999,maxCoordinate:999999,minSize:1000,maxSize:99999'

    // make first_batch_args larger than usual to ensure middle and last batches block before being run
    def first_batch_args = Channel.of('1.0', '5.0', '6.0', '7.0')
    def middle_batch_args = Channel.of('2.0', '3.0')
    def last_batch_args = Channel.of('--completeStackAfterRemoval 4.0')

    RUN_SMALL_WS_JAVA_CLIENT_BATCHES(
        client_class, common_client_args, first_batch_args, middle_batch_args, last_batch_args)
}

workflow {
    TEST_RUN_SMALL_WS_JAVA_CLIENT_BATCHES()
}