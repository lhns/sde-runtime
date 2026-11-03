import java.util.*;
public class Bench {
  static int fib(int n) { return n < 2 ? n : fib(n - 1) + fib(n - 2); }
  public static void main(String[] a) {
    long h = fib(38);
    HashMap<Integer, Integer> m = new HashMap<>();
    for (int i = 0; i < 3000000; i++) m.merge(i % 100003, i, Integer::sum);
    int[] arr = new int[5000000]; long s = 1; for (int i = 0; i < arr.length; i++) { s = s * 6364136223846793005L + 1442695040888963407L; arr[i] = (int) (s >>> 33); }
    Arrays.sort(arr);
    StringBuilder sb = new StringBuilder(); for (int i = 0; i < 300000; i++) sb.append(i);
    System.out.println(h + " " + m.size() + " " + arr[0] + " " + arr[arr.length - 1] + " " + sb.length());
  }
}
