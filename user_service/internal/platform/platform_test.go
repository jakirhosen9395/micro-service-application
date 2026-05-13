package platform

import "testing"

func TestEventTypeSlug(t *testing.T) {
	if got := EventTypeSlug("user.profile.updated"); got != "user_profile_updated" {
		t.Fatalf("slug=%s", got)
	}
}
