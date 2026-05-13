package mongolog

import (
	"context"
	"time"

	"user_service/internal/config"
	"user_service/internal/observability"

	"go.mongodb.org/mongo-driver/bson"
	"go.mongodb.org/mongo-driver/mongo"
	"go.mongodb.org/mongo-driver/mongo/options"
	"go.mongodb.org/mongo-driver/mongo/readpref"
)

type Writer struct {
	client     *mongo.Client
	collection *mongo.Collection
}

func New(ctx context.Context, cfg config.Config) (*Writer, error) {
	client, err := mongo.Connect(ctx, options.Client().ApplyURI(cfg.MongoURI()))
	if err != nil {
		return nil, err
	}
	w := &Writer{client: client, collection: client.Database(cfg.MongoDatabase).Collection(cfg.MongoLogCollection)}
	if err := w.Ping(ctx); err != nil {
		_ = client.Disconnect(context.Background())
		return nil, err
	}
	if err := w.EnsureIndexes(ctx, cfg.Environment); err != nil {
		_ = client.Disconnect(context.Background())
		return nil, err
	}
	return w, nil
}

func (w *Writer) Ping(ctx context.Context) error {
	if w == nil || w.client == nil {
		return mongo.ErrClientDisconnected
	}
	return observability.CaptureDependency(ctx, "MongoDB ping", observability.SpanTypeMongoDB, func(spanCtx context.Context) error {
		return w.client.Ping(spanCtx, readpref.Primary())
	})
}

func (w *Writer) Close(ctx context.Context) error {
	if w == nil || w.client == nil {
		return nil
	}
	return w.client.Disconnect(ctx)
}

func (w *Writer) WriteLog(ctx context.Context, doc map[string]any) error {
	if w == nil || w.collection == nil {
		return nil
	}
	return observability.CaptureDependency(ctx, "MongoDB insert log", observability.SpanTypeMongoDB, func(spanCtx context.Context) error {
		_, err := w.collection.InsertOne(spanCtx, doc)
		return err
	})
}

func (w *Writer) EnsureIndexes(ctx context.Context, environment string) error {
	indexes := []mongo.IndexModel{
		{Keys: bson.D{{Key: "timestamp", Value: -1}}},
		{Keys: bson.D{{Key: "level", Value: 1}, {Key: "timestamp", Value: -1}}},
		{Keys: bson.D{{Key: "event", Value: 1}, {Key: "timestamp", Value: -1}}},
		{Keys: bson.D{{Key: "request_id", Value: 1}}},
		{Keys: bson.D{{Key: "trace_id", Value: 1}}},
		{Keys: bson.D{{Key: "user_id", Value: 1}, {Key: "timestamp", Value: -1}}},
		{Keys: bson.D{{Key: "path", Value: 1}, {Key: "status_code", Value: 1}, {Key: "timestamp", Value: -1}}},
		{Keys: bson.D{{Key: "error_code", Value: 1}, {Key: "timestamp", Value: -1}}},
	}
	if environment != "production" {
		indexes = append(indexes, mongo.IndexModel{Keys: bson.D{{Key: "timestamp", Value: 1}}, Options: options.Index().SetExpireAfterSeconds(int32((14 * 24 * time.Hour).Seconds()))})
	}
	return observability.CaptureDependency(ctx, "MongoDB ensure indexes", observability.SpanTypeMongoDB, func(spanCtx context.Context) error {
		_, err := w.collection.Indexes().CreateMany(spanCtx, indexes)
		return err
	})
}
