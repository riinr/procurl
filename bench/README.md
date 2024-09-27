# Benchmarks

**Disclaimer**: [Benchmarking Is Hard](https://jvns.ca/blog/2016/07/23/rigorous-benchmarking-in-reasonable-time/)
**Disclaimer**: [Operation Costs in CPU Clock Cycles](http://ithare.com/infographics-operation-costs-in-cpu-clock-cycles/)

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
proc fn(): auto = getMonoTime()

let 
  t0 = getMonoTime()
  t1 = schedule fn()  # await/send/schedule if is the case
  t2 = getMonoTime()

  send   = t2 - t0    # How much time it takes to schedule the task,
                      # makes more sense in threads

  jitter = t1 - t0    # How much time it takes to other thread run
                      # this task. again makes more sense in threads
```

We run that 1000 times, get the 5 most commons results.

## Result examples:

#### Reference

```
Tasks:    	1000
Setup:    	000s000ms000us167ns	         	Initializing
Send  100%:	000s000ms097us862ns	000s000ms000us097ns/task	To schedule tasks
Send   88%:	000s000ms000us072ns	 882 tasks	+/-2ns
Send   07%:	000s000ms000us074ns	 077 tasks	+/-2ns
Send   03%:	000s000ms000us070ns	 039 tasks	+/-2ns
Send   00%:	000s000ms000us086ns	 001 tasks	+/-2ns
Send   00%:	000s000ms000us000ns	 000 tasks	+/-2ns
Jitter 99%:	000s000ms000us002ns	 999 tasks	+/-2ns
Jitter 00%:	000s000ms000us000ns	 000 tasks	+/-2ns
Jitter 00%:	000s000ms000us000ns	 000 tasks	+/-2ns
Jitter 00%:	000s000ms000us000ns	 000 tasks	+/-2ns
Jitter 00%:	000s000ms000us000ns	 000 tasks	+/-2ns
Join:     	000s000ms000us038ns	         	Waiting all tasks to complete
Snd+Join: 	000s000ms097us900ns	000s000ms000us097ns/task	Send + Join
Total:    	000s000ms098us116ns
```

#### AsyncDispatch

```
Tasks:    	1000
Setup:    	000s000ms000us301ns	         	Initializing
Send  100%:	000s000ms412us508ns	000s000ms000us412ns/task	To schedule tasks
Send   54%:	000s000ms000us200ns	 547 tasks	+/-025ns
Send   21%:	000s000ms000us175ns	 213 tasks	+/-025ns
Send   16%:	000s000ms000us225ns	 164 tasks	+/-025ns
Send   02%:	000s000ms000us275ns	 020 tasks	+/-025ns
Send   01%:	000s000ms000us300ns	 017 tasks	+/-025ns
Jitter 99%:	000s000ms000us002ns	 999 tasks	+/-002ns
Jitter 00%:	000s000ms000us000ns	 000 tasks	+/-002ns
Jitter 00%:	000s000ms000us000ns	 000 tasks	+/-002ns
Jitter 00%:	000s000ms000us000ns	 000 tasks	+/-002ns
Jitter 00%:	000s000ms000us000ns	 000 tasks	+/-002ns
Join:     	000s000ms000us034ns	         	Waiting all tasks to complete
Snd+Join: 	000s000ms412us542ns	000s000ms000us412ns/task	Send + Join
Total:    	000s000ms412us882ns
```

#### Chronos

```
Tasks:    	1000
Setup:    	000s000ms000us127ns	         	Initializing
Send  100%:	000s000ms267us686ns	000s000ms000us267ns/task	To schedule tasks
Send   38%:	000s000ms000us225ns	 380 tasks	+/-025ns
Send   31%:	000s000ms000us200ns	 310 tasks	+/-025ns
Send   24%:	000s000ms000us250ns	 249 tasks	+/-025ns
Send   05%:	000s000ms000us275ns	 052 tasks	+/-025ns
Send   00%:	000s000ms000us300ns	 003 tasks	+/-025ns
Jitter 99%:	000s000ms000us002ns	 999 tasks	+/-002ns
Jitter 00%:	000s000ms000us000ns	 000 tasks	+/-002ns
Jitter 00%:	000s000ms000us000ns	 000 tasks	+/-002ns
Jitter 00%:	000s000ms000us000ns	 000 tasks	+/-002ns
Jitter 00%:	000s000ms000us000ns	 000 tasks	+/-002ns
Join:     	000s000ms000us027ns	         	Waiting all tasks to complete
Snd+Join: 	000s000ms267us713ns	000s000ms000us267ns/task	Send + Join
Total:    	000s000ms267us887ns
```

#### Dreads

```
Tasks:    	1000
Setup:    	000s000ms108us538ns	         	Initializing
Send  100%:	000s001ms004us656ns	000s000ms001us004ns/task	To schedule tasks
Send   21%:	000s000ms000us450ns	 214 tasks	+/-200ns
Send   14%:	000s000ms000us900ns	 140 tasks	+/-200ns
Send   11%:	000s000ms000us750ns	 116 tasks	+/-200ns
Send   11%:	000s000ms001us050ns	 111 tasks	+/-200ns
Send   10%:	000s000ms000us600ns	 107 tasks	+/-200ns
Jitter 75%:	000s000ms000us200ns	 756 tasks	+/-150ns
Jitter 09%:	000s000ms000us400ns	 093 tasks	+/-150ns
Jitter 01%:	000s000ms001us200ns	 017 tasks	+/-150ns
Jitter 01%:	000s000ms001us800ns	 016 tasks	+/-150ns
Jitter 01%:	000s000ms001us600ns	 015 tasks	+/-150ns
Join:     	000s000ms008us952ns	         	Waiting all tasks to complete
Snd+Join: 	000s001ms013us608ns	000s000ms001us013ns/task	Send + Join
Total:    	000s001ms339us347ns
```

