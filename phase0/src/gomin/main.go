package main

import (
	"fmt"
	"io"
	"net"
	"net/http"
	"os"
	"os/signal"
	"runtime"
	"sync"
	"sync/atomic"
	"syscall"
	"time"
)

func main() {
	switch os.Args[1] {
	case "hello":
		fmt.Println("hello")
	case "goroutines": // many goroutines + channels, no GC call, small allocs
		var wg sync.WaitGroup
		c := make(chan int, 10)
		for i := 0; i < 2000; i++ {
			wg.Add(1)
			go func() { defer wg.Done(); c <- 1; <-c }()
		}
		wg.Wait()
		fmt.Println("ok")
	case "gc":
		for i := 0; i < 5; i++ {
			_ = make([]byte, 1<<24)
			runtime.GC()
		}
		fmt.Println("ok")
	case "spin": // tight loops + GC: GC stop-the-world needs async preemption
		runtime.GOMAXPROCS(4)
		var stop int32
		for i := 0; i < 8; i++ {
			go func() {
				x := 0
				for atomic.LoadInt32(&stop) == 0 {
					x++
				}
			}()
		}
		for i := 0; i < 5; i++ {
			runtime.GC()
			time.Sleep(20 * time.Millisecond)
		}
		atomic.StoreInt32(&stop, 1)
		fmt.Println("ok")
	case "spin1": // spin, but really one P: the env var does not survive the GOMAXPROCS(4) in "spin"
		runtime.GOMAXPROCS(1)
		var stop int32
		for i := 0; i < 8; i++ {
			go func() {
				x := 0
				for atomic.LoadInt32(&stop) == 0 {
					x++
				}
			}()
		}
		for i := 0; i < 5; i++ {
			runtime.GC()
			time.Sleep(20 * time.Millisecond)
		}
		atomic.StoreInt32(&stop, 1)
		fmt.Println("ok")
	case "threads": // about 100 OS threads alive at once
		var wg sync.WaitGroup
		gate := make(chan struct{})
		for i := 0; i < 100; i++ {
			wg.Add(1)
			go func() { defer wg.Done(); runtime.LockOSThread(); <-gate }()
		}
		time.Sleep(200 * time.Millisecond)
		close(gate)
		wg.Wait()
		fmt.Println("ok")
	case "churn": // scheduler churn and GC with no need for signals, under asyncpreemptoff=1
		runtime.GOMAXPROCS(4)
		var stop int32
		for i := 0; i < 8; i++ {
			go func() {
				for atomic.LoadInt32(&stop) == 0 {
					runtime.Gosched()
				}
			}()
		}
		for i := 0; i < 5; i++ {
			runtime.GC()
			time.Sleep(20 * time.Millisecond)
		}
		atomic.StoreInt32(&stop, 1)
		fmt.Println("ok")
	case "spincoop": // same, but the loop calls a function: cooperative preemption suffices
		runtime.GOMAXPROCS(4)
		var stop int32
		for i := 0; i < 8; i++ {
			go func() {
				x := 0
				for atomic.LoadInt32(&stop) == 0 {
					x = inc(x)
				}
			}()
		}
		for i := 0; i < 5; i++ {
			runtime.GC()
			time.Sleep(20 * time.Millisecond)
		}
		atomic.StoreInt32(&stop, 1)
		fmt.Println("ok")
	case "signal":
		usr := make(chan os.Signal, 1)
		signal.Notify(usr, syscall.SIGUSR1, syscall.SIGURG)
		syscall.Kill(os.Getpid(), syscall.SIGUSR1)
		<-usr
		fmt.Println("ok")
	case "http":
		ln, _ := net.Listen("tcp", "127.0.0.1:0")
		go http.Serve(ln, http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { io.WriteString(w, "hello") }))
		r, err := http.Get("http://" + ln.Addr().String())
		if err != nil {
			fmt.Println(err)
			os.Exit(1)
		}
		b, _ := io.ReadAll(r.Body)
		fmt.Println("ok", string(b))
	}
}

//go:noinline
func inc(x int) int { return x + 1 }
