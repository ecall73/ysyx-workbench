build: top.v sim_main.cpp
	verilator --cc --exe --build -j 0 -Wall --trace sim_main.cpp top.v
sim: build
	./obj_dir/Vtop
clean:
	rm -rf obj_dir wave.vcd