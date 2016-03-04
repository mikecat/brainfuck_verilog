TOOL=iverilog
COMMON=brainfuck.v brainfuck_loader.v brainfuck_test.v
NORMAL=brainfuck_cpu.v $(COMMON)
PIPELINE=brainfuck_cpu_pipeline.v $(COMMON)

.PHONY: all
all: brainfuck brainfuck_pipeline

brainfuck: $(NORMAL)
	$(TOOL) -o $@ $(NORMAL)

brainfuck_pipeline: $(PIPELINE)
	$(TOOL) -o $@ $(PIPELINE)

.PHONY: clean
clean:
	rm -rf brainfuck brainfuck_pipeline
