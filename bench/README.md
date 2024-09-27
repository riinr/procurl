# Benchmarks

- **Disclaimer**: [Benchmarking Is Hard](https://jvns.ca/blog/2016/07/23/rigorous-benchmarking-in-reasonable-time/)
- **Disclaimer**: [Operation Costs in CPU Clock Cycles](http://ithare.com/infographics-operation-costs-in-cpu-clock-cycles/)

The main objective is meausre noise of this library. But we also measure other
libraries for reference.

The noise of instrumentation is ~65ns in my computer, with room for error, ~100ns.

```nim
let 
  t0 = getMonoTime()
  t1 = getMonoTime()
  precision = t1 - t0

assert 100 > precision and precision > 25
```

We do that taking the time before the function call, inside the function, and
after the function.

```nim
proc fn(t1: var MonoTime): void =
  t1 = getMonoTime()


let t0 = getMonoTime()
var t1: MonoTime
schedule fn(t1)         # await/send/schedule if is the case
let t2 = getMonoTime()

let send   = t2 - t0    # How much time it takes to schedule the task,
                        # makes more sense in threads

let jitter = t1 - t0    # How much time it takes to other thread run
                        # this task. again makes more sense in threads
```

We run that 1000 times, get the 5 most commons results.

## Result examples:

#### Reference

```
Tasks:    	1000
Setup:    	           167ns	         	Initializing
Send  100%:	      097us862ns	0097ns/task	To schedule tasks
Send   88%:	            72ns	 882 tasks	+/-2ns
Send   07%:	            74ns	  77 tasks	+/-2ns
Send   03%:	            70ns	  39 tasks	+/-2ns
Send   00%:	            86ns	  01 tasks	+/-2ns
Send   00%:	             0ns	   0 tasks	+/-2ns
Jitter 99%:	             2ns	 999 tasks	+/-2ns
Jitter 00%:	             0ns	   0 tasks	+/-2ns
Jitter 00%:	             0ns	   0 tasks	+/-2ns
Jitter 00%:	             0ns	   0 tasks	+/-2ns
Jitter 00%:	             0ns	   0 tasks	+/-2ns
Join:     	            38ns	         	Waiting all tasks to complete
Snd+Join: 	      097us900ns	097ns/task	Send + Join
Total:    	      098us116ns
```

#### AsyncDispatch

```
Tasks:    	1000
Setup:    	           301ns	         	Initializing
Send  100%:	      412us508ns	412ns/task	To schedule tasks
Send   54%:	           200ns	 547 tasks	+/-025ns
Send   21%:	           175ns	 213 tasks	+/-025ns
Send   16%:	           225ns	 164 tasks	+/-025ns
Send   02%:	           275ns	 020 tasks	+/-025ns
Send   01%:	           300ns	 017 tasks	+/-025ns
Jitter 99%:	             2ns	 999 tasks	+/-002ns
Jitter 00%:	             0ns	   0 tasks	+/-002ns
Jitter 00%:	             0ns	   0 tasks	+/-002ns
Jitter 00%:	             0ns	   0 tasks	+/-002ns
Jitter 00%:	             0ns	   0 tasks	+/-002ns
Join:     	            34ns	         	Waiting all tasks to complete
Snd+Join: 	      412us542ns	412ns/task	Send + Join
Total:    	      412us882ns
```

#### Chronos

```
Tasks:    	1000
Setup:    	             127ns	         	Initializing
Send  100%:	        267us686ns	267ns/task	To schedule tasks
Send   38%:	             225ns	 380 tasks	+/-025ns
Send   31%:	             200ns	 310 tasks	+/-025ns
Send   24%:	             250ns	 249 tasks	+/-025ns
Send   05%:	             275ns	 052 tasks	+/-025ns
Send   00%:	             300ns	 003 tasks	+/-025ns
Jitter 99%:	               2ns	 999 tasks	+/-002ns
Jitter 00%:	               0ns	   0 tasks	+/-002ns
Jitter 00%:	               0ns	   0 tasks	+/-002ns
Jitter 00%:	               0ns	   0 tasks	+/-002ns
Jitter 00%:	               0ns	   0 tasks	+/-002ns
Join:     	              27ns	         	Waiting all tasks to complete
Snd+Join: 	        267us713ns	267ns/task	Send + Join
Total:    	        267us887ns
```

#### Dreads

```
Tasks:    	1000
Setup:    	        108us538ns	         	Initializing
Send  100%:	     1ms004us656ns	1us004ns/task	To schedule tasks
Send   21%:	             450ns	 214 tasks	+/-200ns
Send   14%:	             900ns	 140 tasks	+/-200ns
Send   11%:	             750ns	 116 tasks	+/-200ns
Send   11%:	          1us050ns	 111 tasks	+/-200ns
Send   10%:	             600ns	 107 tasks	+/-200ns
Jitter 75%:	             200ns	 756 tasks	+/-150ns
Jitter 09%:	             400ns	 093 tasks	+/-150ns
Jitter 01%:	          1us200ns	 017 tasks	+/-150ns
Jitter 01%:	          1us800ns	 016 tasks	+/-150ns
Jitter 01%:	          1us600ns	 015 tasks	+/-150ns
Join:     	          8us952ns	         	Waiting all tasks to complete
Snd+Join: 	     1ms013us608ns	1us013ns/task	Send + Join
Total:    	     1ms339us347ns
```

