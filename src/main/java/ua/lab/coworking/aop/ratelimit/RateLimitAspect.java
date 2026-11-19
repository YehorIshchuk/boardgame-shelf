package ua.lab.coworking.aop.ratelimit;

import java.time.Clock;
import java.util.ArrayDeque;
import java.util.Deque;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;

import org.aspectj.lang.ProceedingJoinPoint;
import org.aspectj.lang.annotation.Around;
import org.aspectj.lang.annotation.Aspect;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.core.annotation.Order;
import org.springframework.security.authentication.AnonymousAuthenticationToken;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.stereotype.Component;

/**
 * Advice @Around для {@link RateLimited}.
 *
 * Алгоритм — ковзне вікно: для пари (метод, користувач) зберігаються моменти останніх викликів.
 * Якщо за останні windowSeconds їх уже maxCalls — {@code proceed()} НЕ викликається, кидається
 * {@link RateLimitExceededException}. Інакше виклик фіксується і метод виконується.
 *
 * {@code @Order(0)} — перевірка ліміту виконується раніше за @PreAuthorize (порядок 200) і транзакцію
 * (LOWEST_PRECEDENCE), тобто зайвий виклик відсікається до будь-якої роботи з БД.
 *
 * Важливо: НЕ можна ставити Ordered.HIGHEST_PRECEDENCE. Тоді аспект опиняється раніше за службовий
 * ExposeInvocationInterceptor (порядок HIGHEST_PRECEDENCE + 1), Spring ще не встигає прив'язати
 * параметри pointcut'а (@annotation(rateLimited)), і виклик падає з помилкою
 * "Required to bind 2 arguments, but only bound 1 (JoinPointMatch was NOT bound in invocation)".
 */
@Aspect
@Component
@Order(0)
public class RateLimitAspect {

    private static final Logger log = LoggerFactory.getLogger(RateLimitAspect.class);

    private final Clock clock;
    private final Map<String, Deque<Long>> callsByKey = new ConcurrentHashMap<>();

    public RateLimitAspect(Clock clock) {
        this.clock = clock;
    }

    @Around("@annotation(rateLimited)")
    public Object enforce(ProceedingJoinPoint joinPoint, RateLimited rateLimited) throws Throwable {
        String user = currentUser();
        String key = joinPoint.getSignature().toShortString() + "|" + user;
        long now = clock.millis();
        long windowMillis = rateLimited.windowSeconds() * 1000L;

        Deque<Long> calls = callsByKey.computeIfAbsent(key, k -> new ArrayDeque<>());
        synchronized (calls) {
            while (!calls.isEmpty() && calls.peekFirst() <= now - windowMillis) {
                calls.pollFirst();
            }
            if (calls.size() >= rateLimited.maxCalls()) {
                long retryAfterSeconds = Math.max(1, (calls.peekFirst() + windowMillis - now + 999) / 1000);
                log.warn("Rate limit: користувач {} перевищив ліміт {} за {} с для {}",
                        user, rateLimited.maxCalls(), rateLimited.windowSeconds(), joinPoint.getSignature().toShortString());
                throw new RateLimitExceededException(
                        "Забагато %s: дозволено не більше %d за %d с. Спробуйте знову через %d с"
                                .formatted(rateLimited.action(), rateLimited.maxCalls(),
                                        rateLimited.windowSeconds(), retryAfterSeconds),
                        retryAfterSeconds);
            }
            calls.addLast(now);
        }
        return joinPoint.proceed();
    }

    private static String currentUser() {
        Authentication auth = SecurityContextHolder.getContext().getAuthentication();
        if (auth == null || auth instanceof AnonymousAuthenticationToken) {
            return "anonymous";
        }
        return auth.getName();
    }
}
