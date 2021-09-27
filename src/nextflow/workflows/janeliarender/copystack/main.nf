#!/usr/bin/env nextflow

nextflow.enable.dsl = 2

include {
    GET_STACK_Z_VALUES_JSON;
} from '../../../modules/janeliarender/wsscriptclient/main.nf'

include {
    SPLIT_JSON_ARRAY_TEXT_INTO_FML_CHANNELS;
} from '../../../subworkflows/janeliarender/json/main.nf'

include {
    RUN_SMALL_WS_JAVA_CLIENT_BATCHES;
} from '../../../subworkflows/janeliarender/wsjavaclient/main.nf'

// TODO: why do take variables need to scoped with 'cs' prefix or cause compile errors?
//   wondering if this will be a problem for multiple uses in a single workflow

// TODO: add support for keepExisting, excludedColumnsJson

// TODO: should there be any output?

workflow COPY_STACK {
    take:
    csBaseDataUrl
    csOwner
    csProject
    csFromStack
    csToStack
    csMinZ
    csMaxZ

    main:
    def client_class = 'org.janelia.render.client.CopyStackClient'

    // TODO: why does this have to go before GET_STACK_Z_VALUES_JSON call (causes compile error otherwise)?
    def common_client_args =
        "--baseDataUrl ${csBaseDataUrl} --owner ${csOwner} --project ${csProject} " +
        "--fromStack ${csFromStack} --toStack ${csToStack} --keepExisting"

    // TODO: make minZ and maxZ optional
    def minZString = csMinZ.toString()
    def maxZString = csMaxZ.toString()

    GET_STACK_Z_VALUES_JSON(csBaseDataUrl, csOwner, csProject, csFromStack, minZString, maxZString)
    SPLIT_JSON_ARRAY_TEXT_INTO_FML_CHANNELS(GET_STACK_Z_VALUES_JSON.out.z_values_json_text)

    def first_batch_args = SPLIT_JSON_ARRAY_TEXT_INTO_FML_CHANNELS.out.first_ch.map {
        "--z $it"
    }
    def middle_batch_args = SPLIT_JSON_ARRAY_TEXT_INTO_FML_CHANNELS.out.middle_ch.map {
        "--z $it"
    }
    def last_batch_args = SPLIT_JSON_ARRAY_TEXT_INTO_FML_CHANNELS.out.last_ch.map {
        "--completeToStackAfterCopy --z $it"
    }

    RUN_SMALL_WS_JAVA_CLIENT_BATCHES(
        client_class, common_client_args, first_batch_args, middle_batch_args, last_batch_args)
}