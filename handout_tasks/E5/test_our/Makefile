build: our.v sim_main.cpp
	verilator --cc --exe --build -j 0 -Wall sim_main.cpp our.v
sim: build
	./obj_dir/Vour
clean:
	rm -rf obj_dir