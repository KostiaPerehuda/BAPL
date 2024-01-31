return {
    parser = {
        display_ast = 1 << 0,
        everything = 0x1,
    },

    compiler = {
        display_compiled_code = 1 << 1,
        everything = 0x2,
    },

    runner = {
        trace_function_calls  = 1 << 2,
        trace_every_cycle     = 1 << 3,
        everything = 0xC,
    },
    
    nothing    = 0x0,
    everything = 0xF,
}