package cache

import (
	"context"
	"encoding/json"
	"strings"
	"time"

	"user_service/internal/config"
	"user_service/internal/observability"

	"github.com/redis/go-redis/v9"
)

type Client struct {
	cfg config.Config
	rdb *redis.Client
}

func New(ctx context.Context, cfg config.Config) (*Client, error) {
	client := redis.NewClient(&redis.Options{Addr: cfg.RedisAddress(), Password: cfg.RedisPassword, DB: cfg.RedisDB})
	c := &Client{cfg: cfg, rdb: client}
	if err := c.Ping(ctx); err != nil {
		_ = client.Close()
		return nil, err
	}
	return c, nil
}

func (c *Client) Close() error {
	if c == nil || c.rdb == nil {
		return nil
	}
	return c.rdb.Close()
}

func (c *Client) Ping(ctx context.Context) error {
	if c == nil || c.rdb == nil {
		return redis.Nil
	}
	return observability.CaptureDependency(ctx, "Redis ping", observability.SpanTypeRedis, func(spanCtx context.Context) error {
		return c.rdb.Ping(spanCtx).Err()
	})
}

func (c *Client) GetJSON(ctx context.Context, key string, dest any) (bool, error) {
	if c == nil || c.rdb == nil {
		return false, redis.Nil
	}
	var b []byte
	err := observability.CaptureDependencyNoError(ctx, "Redis GET", observability.SpanTypeRedis, func(spanCtx context.Context) error {
		var getErr error
		b, getErr = c.rdb.Get(spanCtx, key).Bytes()
		return getErr
	})
	if err == redis.Nil {
		return false, nil
	}
	if err != nil {
		return false, err
	}
	if err := json.Unmarshal(b, dest); err != nil {
		_ = observability.CaptureDependencyNoError(ctx, "Redis DEL stale JSON", observability.SpanTypeRedis, func(spanCtx context.Context) error {
			return c.rdb.Del(spanCtx, key).Err()
		})
		return false, nil
	}
	return true, nil
}

func (c *Client) SetJSON(ctx context.Context, key string, value any) error {
	if c == nil || c.rdb == nil {
		return nil
	}
	b, err := json.Marshal(value)
	if err != nil {
		return err
	}
	return observability.CaptureDependency(ctx, "Redis SET", observability.SpanTypeRedis, func(spanCtx context.Context) error {
		return c.rdb.Set(spanCtx, key, b, c.cfg.CacheTTL()).Err()
	})
}

func (c *Client) Delete(ctx context.Context, keys ...string) error {
	if c == nil || c.rdb == nil || len(keys) == 0 {
		return nil
	}
	return observability.CaptureDependency(ctx, "Redis DEL", observability.SpanTypeRedis, func(spanCtx context.Context) error {
		return c.rdb.Del(spanCtx, keys...).Err()
	})
}

func (c *Client) DeletePrefix(ctx context.Context, prefix string) error {
	if c == nil || c.rdb == nil {
		return nil
	}
	if !strings.HasPrefix(prefix, c.cfg.Environment+":"+c.cfg.ServiceName+":") {
		return nil
	}
	var iter *redis.ScanIterator
	if err := observability.CaptureDependency(ctx, "Redis SCAN", observability.SpanTypeRedis, func(spanCtx context.Context) error {
		iter = c.rdb.Scan(spanCtx, 0, prefix+"*", 100).Iterator()
		return nil
	}); err != nil {
		return err
	}
	keys := make([]string, 0, 100)
	for iter.Next(ctx) {
		keys = append(keys, iter.Val())
		if len(keys) == 100 {
			if err := observability.CaptureDependency(ctx, "Redis DEL", observability.SpanTypeRedis, func(spanCtx context.Context) error {
				return c.rdb.Del(spanCtx, keys...).Err()
			}); err != nil {
				return err
			}
			keys = keys[:0]
		}
	}
	if err := iter.Err(); err != nil {
		return err
	}
	if len(keys) > 0 {
		return observability.CaptureDependency(ctx, "Redis DEL", observability.SpanTypeRedis, func(spanCtx context.Context) error {
			return c.rdb.Del(spanCtx, keys...).Err()
		})
	}
	return nil
}

func (c *Client) Lock(ctx context.Context, key string, ttl time.Duration) (bool, error) {
	if c == nil || c.rdb == nil {
		return false, nil
	}
	var ok bool
	err := observability.CaptureDependency(ctx, "Redis SETNX", observability.SpanTypeRedis, func(spanCtx context.Context) error {
		var setErr error
		ok, setErr = c.rdb.SetNX(spanCtx, key, "1", ttl).Result()
		return setErr
	})
	return ok, err
}
