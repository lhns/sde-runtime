package main

import (
	"fmt"
	"io"
	"net"
	"net/http"
	"os"
	"os/signal"
	"runtime"
	"strings"
	"sync"
	"sync/atomic"
	"syscall"
	"time"
)

func main() {
	runtime.GOMAXPROCS(4)
	urg := make(chan os.Signal, 100000)
	signal.Notify(urg, syscall.SIGURG)
	usr := make(chan os.Signal, 1)
	signal.Notify(usr, syscall.SIGUSR1)
	var wg sync.WaitGroup
	var tot int64
	for i := 0; i < 2000; i++ {
		wg.Add(1)
		go func(i int) {
			defer wg.Done()
			var keep [][]byte
			for j := 0; j < 50; j++ {
				keep = append(keep, make([]byte, 1<<14))
			}
			atomic.AddInt64(&tot, int64(len(keep)+i%3))
		}(i)
	}
	stop := int32(0)
	for i := 0; i < 8; i++ { // tight loops need async preemption (SIGURG)
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
	wg.Wait()
	atomic.StoreInt32(&stop, 1)
	fmt.Println("goroutines ok", tot)
	syscall.Kill(os.Getpid(), syscall.SIGUSR1)
	select {
	case <-usr:
		fmt.Println("sigusr1 ok")
	case <-time.After(5 * time.Second):
		fmt.Println("sigusr1 TIMEOUT")
	}
	fmt.Println("sigurg>0:", len(urg) > 0)
	ln, _ := net.Listen("tcp", "127.0.0.1:0")
	go http.Serve(ln, http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { io.WriteString(w, "hello") }))
	r, err := http.Get("http://" + ln.Addr().String())
	if err != nil {
		fmt.Println("http err", err)
		os.Exit(1)
	}
	b, _ := io.ReadAll(r.Body)
	fmt.Println("http body", string(b))
	m, _ := os.ReadFile("/proc/self/maps")
	fmt.Printf("DRINFO maps_dr=%d\n", strings.Count(string(m), "dynamorio"))
}
