// TODO: learn "proper" unit test framework for Nextflow/Groovy
// see https://nf-co.re/tools/#create-a-module-test-config-file

def assertEquals(context, expected, actual) {
    if (actual == expected) {
        println("test succeeded, ${context} was ${actual}")
    } else {
        // needed to print error and then throw exception so that detailed message is not lost
        // this is why I couldn't just use the built-in assert statement
        def errorMessage = "test failed: ${context} was ${actual} instead of ${expected}"
        println(errorMessage)
        throw new IllegalArgumentException(errorMessage)
    }
}