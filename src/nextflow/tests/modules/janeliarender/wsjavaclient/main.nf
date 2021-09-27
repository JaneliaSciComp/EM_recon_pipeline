#!/usr/bin/env nextflow

// Test workflow structure copied from
//   https://github.com/nf-core/modules/blob/master/tests/modules/blast/blastn/main.nf
// nf-core create tool will generate similar structure

// TODO: improve understanding of nf-core test framework (hoping that it won't be too hard to adapt these tests later)

nextflow.enable.dsl = 2

include {
    assertEquals;
} from '../../../modules/janeliarender/testutils.nf'

include {
    RUN_SMALL_WS_JAVA_CLIENT
} from '../../../../modules/janeliarender/wsjavaclient/main.nf'

workflow TEST_RUN_SMALL_WS_JAVA_CLIENT {
    client_class = 'org.janelia.render.client.ValidateTilesClient'
    common_client_args = '--baseDataUrl http://renderer-dev.int.janelia.org:8080/render-ws/v1 ' +
                         '--owner flyTEM --project FAFB00 --stack v14_align_tps_20170818 ' +
                         '--validatorClass org.janelia.alignment.spec.validator.TemTileSpecValidator ' +
                         '--validatorData minCoordinate:-999999,maxCoordinate:999999,minSize:1000,maxSize:99999'
    job_specific_client_args = Channel.of('1.0', '2.0')

    RUN_SMALL_WS_JAVA_CLIENT(client_class, common_client_args, job_specific_client_args, true)

    def error_count_sum = RUN_SMALL_WS_JAVA_CLIENT.out.client_result.sum {
        def (error_count, client_log) = it
        error_count.toInteger()
    }.collect()

    error_count_sum.map {
        assertEquals("error count sum", 89, it[0])
    }
}

workflow {
    TEST_RUN_SMALL_WS_JAVA_CLIENT()
}