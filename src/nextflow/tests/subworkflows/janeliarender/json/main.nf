#!/usr/bin/env nextflow

nextflow.enable.dsl = 2

include {
    assertEquals;
} from '../../../modules/janeliarender/testutils.nf'

include {
    SPLIT_JSON_ARRAY_TEXT_INTO_FML_CHANNELS as SPLIT_0;
    SPLIT_JSON_ARRAY_TEXT_INTO_FML_CHANNELS as SPLIT_1;
    SPLIT_JSON_ARRAY_TEXT_INTO_FML_CHANNELS as SPLIT_2;
    SPLIT_JSON_ARRAY_TEXT_INTO_FML_CHANNELS as SPLIT_3;
} from '../../../../subworkflows/janeliarender/json/main.nf'

workflow TEST_SPLIT_JSON_ARRAY_TEXT_INTO_0_FML_CHANNELS {
    def z_values_json_text = Channel.of('[]')

    SPLIT_0(z_values_json_text)

    SPLIT_0.out.first_ch.count().map {
        assertEquals("split 0 first_ch count", 0, it)
    }

    SPLIT_0.out.middle_ch.count().map {
        assertEquals("split 0 middle_ch count", 0, it)
    }

    SPLIT_0.out.last_ch.count().map {
        assertEquals("split 0 last_ch count", 0, it)
    }
}

workflow TEST_SPLIT_JSON_ARRAY_TEXT_INTO_1_FML_CHANNEL {
    def z_values_json_text = Channel.of('[13.0]')

    SPLIT_1(z_values_json_text)

    SPLIT_1.out.first_ch.count().map {
        assertEquals("split 1 first_ch count", 0, it)
    }

    SPLIT_1.out.middle_ch.count().map {
        assertEquals("split 1 middle_ch count", 0, it)
    }

    SPLIT_1.out.last_ch.count().map {
        assertEquals("split 1 last_ch count", 1, it)
    }

    SPLIT_1.out.last_ch.map {
        assertEquals("split 1 last_ch value", 13.0, it)
    }
}

workflow TEST_SPLIT_JSON_ARRAY_TEXT_INTO_2_FML_CHANNELS {
    def z_values_json_text = Channel.of('[11.0, 12.0]')

    SPLIT_2(z_values_json_text)

    SPLIT_2.out.first_ch.count().map {
        assertEquals("split 2 first_ch count", 1, it)
    }

    SPLIT_2.out.first_ch.map {
        assertEquals("split 2 first_ch value", 11.0, it)
    }

    SPLIT_2.out.middle_ch.count().map {
        assertEquals("split 2 middle_ch count", 0, it)
    }

    SPLIT_2.out.last_ch.count().map {
        assertEquals("split 2 last_ch count", 1, it)
    }

    SPLIT_2.out.last_ch.map {
        assertEquals("split 2 last_ch value", 12.0, it)
    }
}

workflow TEST_SPLIT_JSON_ARRAY_TEXT_INTO_3_FML_CHANNELS {
    def z_values_json_text = Channel.of('[9.0, 10.0, 11.0, 12.0, 13.0, 14.0, 15.0]')

    SPLIT_3(z_values_json_text)

    SPLIT_3.out.first_ch.count().map {
        assertEquals("split 3 first_ch count", 1, it)
    }

    SPLIT_3.out.first_ch.map {
        assertEquals("split 3 first_ch value", 9.0, it)
    }

    def expectedMiddleChannelCount = 5
    SPLIT_3.out.middle_ch.count().map {
        assertEquals("split 3 middle_ch count", expectedMiddleChannelCount, it)
    }

    SPLIT_3.out.middle_ch.collect().map {
        assertEquals("split 3 middle_ch list size", expectedMiddleChannelCount, it.size())
        assertEquals("split 3 middle_ch first value", 10.0, it.get(0))
        assertEquals("split 3 middle_ch last value", 14.0, it.get(expectedMiddleChannelCount - 1))
    }

    SPLIT_3.out.last_ch.count().map {
        assertEquals("split 3 last_ch count", 1, it)
    }

    SPLIT_3.out.last_ch.map {
        assertEquals("split 3 last_ch value", 15.0, it)
    }
}

workflow {
    TEST_SPLIT_JSON_ARRAY_TEXT_INTO_0_FML_CHANNELS()
    TEST_SPLIT_JSON_ARRAY_TEXT_INTO_1_FML_CHANNEL()
    TEST_SPLIT_JSON_ARRAY_TEXT_INTO_2_FML_CHANNELS()
    TEST_SPLIT_JSON_ARRAY_TEXT_INTO_3_FML_CHANNELS()
}