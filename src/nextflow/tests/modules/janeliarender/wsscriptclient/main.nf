#!/usr/bin/env nextflow

nextflow.enable.dsl = 2

include {
    assertEquals;
} from '../../../modules/janeliarender/testutils.nf'

include {
    GET_STACK_Z_VALUES_JSON;
} from '../../../../modules/janeliarender/wsscriptclient/main.nf'

include {
    SPLIT_JSON_ARRAY_TEXT_INTO_FML_CHANNELS;
} from '../../../../subworkflows/janeliarender/json/main.nf'

workflow TEST_GET_STACK_Z_VALUES_JSON {

    def expectedFirstZ = 9
    def expectedLastZ = 15
    def expectedCount = expectedLastZ - expectedFirstZ + 1

    GET_STACK_Z_VALUES_JSON(
        'http://renderer-dev.int.janelia.org:8080/render-ws/v1',
        'Z0720_07m_BR', 'Sec06', 'v1_acquire',
        expectedFirstZ.toString(), expectedLastZ.toString())

    SPLIT_JSON_ARRAY_TEXT_INTO_FML_CHANNELS(GET_STACK_Z_VALUES_JSON.out.z_values_json_text)

    SPLIT_JSON_ARRAY_TEXT_INTO_FML_CHANNELS.out.first_ch.map {
        assertEquals("z first_ch value", 9.0, it)
    }

    SPLIT_JSON_ARRAY_TEXT_INTO_FML_CHANNELS.out.middle_ch.collect().map {
        assertEquals("z middle_ch list size", 5, it.size())
        assertEquals("z middle_ch first value", 10.0, it.get(0))
        assertEquals("z middle_ch last value", 14.0, it.get(4))
    }

    SPLIT_JSON_ARRAY_TEXT_INTO_FML_CHANNELS.out.last_ch.map {
        assertEquals("z last_ch value", 15.0, it)
    }
}

workflow {
    TEST_GET_STACK_Z_VALUES_JSON()
}