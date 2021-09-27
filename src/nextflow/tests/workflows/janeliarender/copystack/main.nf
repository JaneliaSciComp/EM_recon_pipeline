#!/usr/bin/env nextflow

nextflow.enable.dsl = 2

include {
    COPY_STACK;
} from '../../../../workflows/janeliarender/copystack/main.nf'


workflow TEST_COPY_STACK {
    def baseDataUrl = "http://10.40.3.162:8080/render-ws/v1"
    def owner = "Z0720_07m_BR"
    def project = "Sec07"
    def fromStack = "v1_acquire"
    def toStack = "test_nf"
    def minZ = 1
    def maxZ = 10
    COPY_STACK(baseDataUrl, owner, project, fromStack, toStack, minZ, maxZ)
//     COPY_STACK(baseDataUrl, owner, project)
}

workflow {
    TEST_COPY_STACK()
}