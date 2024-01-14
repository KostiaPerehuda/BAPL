public class Activity2 {
    public static void main(String[] args) {
        Object[] a = new Object[1];
        a[0] = a;
        System.out.println(((Object[])((Object[])a[0])[0])[0] == a); // --> true
    }
}